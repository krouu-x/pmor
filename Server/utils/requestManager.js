/**
 * Request Manager - Provides request-level deduplication, bounded concurrency,
 * per-request timeouts, circuit breaker, result caching, and structured logging for provider calls.
 */

// ============================================================================
// CONFIGURATION
// ============================================================================

const PROVIDER_CONCURRENCY_LIMIT = 5;

// Simple concurrency limiter (replacement for p-limit which is ESM-only in v6+)
function createConcurrencyLimiter(limit) {
  let running = 0;
  const queue = [];

  function next() {
    if (running < limit && queue.length > 0) {
      const { fn, resolve, reject } = queue.shift();
      running++;
      Promise.resolve().then(() => fn())
        .then(resolve, reject)
        .finally(() => {
          running--;
          next();
        });
    }
  }

  return function(fn) {
    return new Promise((resolve, reject) => {
      queue.push({ fn, resolve, reject });
      next();
    });
  };
}

const providerLimiter = createConcurrencyLimiter(PROVIDER_CONCURRENCY_LIMIT);
const PROVIDER_TIMEOUTS = {
  'castletv': 15000,
  'showbox': 30000,
  '4khdhub': 25000,
  'zxcstreams': 20000,
  'netmirror': 25000,
  'onetouchtv': 20000,
  'hdghartv': 15000,
  'vaplayer': 15000,
  'vidlink': 15000,
  'videasy': 15000,
  'vixsrc': 15000,
  'dahmermovies': 15000,
  'streamflix': 15000,
  'lordflix': 15000,
  'notorrent': 15000,
  'uhdmovies': 15000,
  'default': 10000
};

const CIRCUIT_BREAKER_THRESHOLD = 5;
const CIRCUIT_BREAKER_TIMEOUT_MS = 60000;
const CIRCUIT_BREAKER_HALF_OPEN_MAX = 3;

// Cache TTLs
const REQUEST_DEDUPE_TTL_MS = 30000;    // 30s for in-flight request deduplication
const PROVIDER_RESULT_TTL_MS = 5 * 60 * 1000;  // 5min for successful provider results
const PROVIDER_ERROR_TTL_MS = 60000;    // 1min for provider errors

// ============================================================================
// STATE
// ============================================================================

// In-flight request deduplication cache
// Key: `${type}:${tmdbId}:${season}:${episode}`
// Value: { promise, timestamp, resolve, reject }
const requestCache = new Map();

// Provider result cache (successful responses)
// Key: `${providerName}:${type}:${tmdbId}:${season}:${episode}`
// Value: { data, timestamp, providerTimings }
const providerResultCache = new Map();

// Provider error cache (failed responses)
// Key: `${providerName}:${type}:${tmdbId}:${season}:${episode}`
// Value: { error, timestamp }
const providerErrorCache = new Map();

// Circuit breaker state per provider
const circuitBreakers = new Map();

// Metrics
const metrics = {
  deduplicationHits: 0,
  cacheHits: 0,
  cacheMisses: 0,
  providerCalls: 0,
  providerSuccesses: 0,
  providerFailures: 0,
  providerTimeouts: 0,
  circuitBreakerOpens: 0,
  totalDurationMs: 0,
  validationCalls: 0,
  validationCacheHits: 0
};

// Cleanup intervals
setInterval(() => {
  const now = Date.now();
  for (const [key, entry] of requestCache.entries()) {
    if (now - entry.timestamp > REQUEST_DEDUPE_TTL_MS) {
      requestCache.delete(key);
    }
  }
  for (const [key, entry] of providerResultCache.entries()) {
    if (now - entry.timestamp > PROVIDER_RESULT_TTL_MS) {
      providerResultCache.delete(key);
    }
  }
  for (const [key, entry] of providerErrorCache.entries()) {
    if (now - entry.timestamp > PROVIDER_ERROR_TTL_MS) {
      providerErrorCache.delete(key);
    }
  }
}, 60000).unref();

// ============================================================================
// CIRCUIT BREAKER
// ============================================================================

function getCircuitBreaker(providerName) {
  if (!circuitBreakers.has(providerName)) {
    circuitBreakers.set(providerName, {
      failures: 0,
      successes: 0,
      lastFailure: 0,
      lastSuccess: 0,
      state: 'closed', // closed, open, half-open
      halfOpenSuccesses: 0
    });
  }
  return circuitBreakers.get(providerName);
}

function recordSuccess(providerName) {
  const cb = getCircuitBreaker(providerName);
  cb.failures = 0;
  cb.successes++;
  cb.lastSuccess = Date.now();

  if (cb.state === 'half-open') {
    cb.halfOpenSuccesses++;
    if (cb.halfOpenSuccesses >= CIRCUIT_BREAKER_HALF_OPEN_MAX) {
      cb.state = 'closed';
      cb.halfOpenSuccesses = 0;
      logStructured('info', 'Circuit breaker closed', { provider: providerName, state: 'closed' });
    }
  } else {
    cb.state = 'closed';
  }
}

function recordFailure(providerName) {
  const cb = getCircuitBreaker(providerName);
  cb.failures++;
  cb.lastFailure = Date.now();

  if (cb.state === 'half-open') {
    // Any failure in half-open goes back to open
    cb.state = 'open';
    cb.halfOpenSuccesses = 0;
    logStructured('warn', 'Circuit breaker reopened after half-open failure', { provider: providerName });
  } else if (cb.failures >= CIRCUIT_BREAKER_THRESHOLD && cb.state === 'closed') {
    cb.state = 'open';
    metrics.circuitBreakerOpens++;
    logStructured('warn', 'Circuit breaker opened', {
      provider: providerName,
      failures: cb.failures,
      threshold: CIRCUIT_BREAKER_THRESHOLD
    });
  }
}

function isCircuitOpen(providerName) {
  const cb = getCircuitBreaker(providerName);
  if (cb.state === 'open') {
    // Check if timeout has passed to move to half-open
    if (Date.now() - cb.lastFailure > CIRCUIT_BREAKER_TIMEOUT_MS) {
      cb.state = 'half-open';
      cb.halfOpenSuccesses = 0;
      logStructured('info', 'Circuit breaker half-open', { provider: providerName });
      return false; // Allow one request through
    }
    return true;
  }
  return false;
}

// ============================================================================
// STRUCTURED LOGGING
// ============================================================================

/**
 * Structured logging with consistent fields for observability
 * @param {'info'|'warn'|'error'|'debug'} level
 * @param {string} message
 * @param {object} context - Must include: provider, stage, requestId, tmdbId, type
 * @param {number} [context.durationMs] - Optional duration in milliseconds
 * @param {string} [context.status] - 'success' | 'failed' | 'timeout' | 'cache_hit' | 'cache_miss'
 */
function logStructured(level, message, context = {}) {
  const logEntry = {
    level,
    message,
    timestamp: new Date().toISOString(),
    ...context
  };

  // Ensure required fields
  if (!logEntry.provider) logEntry.provider = context.provider || 'unknown';
  if (!logEntry.stage) logEntry.stage = context.stage || 'unknown';
  if (!logEntry.requestId) logEntry.requestId = context.requestId || 'none';
  if (!logEntry.tmdbId) logEntry.tmdbId = context.tmdbId || 'none';
  if (!logEntry.type) logEntry.type = context.type || 'unknown';

  const output = JSON.stringify(logEntry);

  switch (level) {
    case 'error':
      console.error(output);
      break;
    case 'warn':
      console.warn(output);
      break;
    case 'debug':
      if (process.env.LOG_LEVEL === 'debug') console.log(output);
      break;
    default:
      console.log(output);
  }
}

/**
 * Create a structured logger bound to a context
 * @param {object} context - Base context for all log entries
 * @returns {object} Logger with info, warn, error, debug methods
 */
function createLogger(context = {}) {
  const baseContext = {
    timestamp: new Date().toISOString(),
    ...context
  };

  return {
    info: (message, extra = {}) => logStructured('info', message, { ...baseContext, ...extra }),
    warn: (message, extra = {}) => logStructured('warn', message, { ...baseContext, ...extra }),
    error: (message, extra = {}) => logStructured('error', message, { ...baseContext, ...extra }),
    debug: (message, extra = {}) => logStructured('debug', message, { ...baseContext, ...extra }),

    // Convenience methods for structured stages
    stageStart: (stage, extra = {}) => logStructured('info', `Stage started: ${stage}`, {
      ...baseContext,
      stage,
      status: 'started',
      ...extra
    }),
    stageEnd: (stage, durationMs, status = 'success', extra = {}) => logStructured('info', `Stage completed: ${stage}`, {
      ...baseContext,
      stage,
      durationMs,
      status,
      ...extra
    }),
    cacheEvent: (eventType, key, extra = {}) => logStructured('info', `Cache ${eventType}`, {
      ...baseContext,
      stage: 'cache',
      cacheEvent: eventType,
      cacheKey: key,
      ...extra
    })
  };
}

// Generate a request correlation ID
function generateRequestId() {
  return `req_${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;
}

// ============================================================================
// CACHE HELPERS
// ============================================================================

function getRequestCacheKey(ctx) {
  return `${ctx.type}:${ctx.tmdbId}:${ctx.season || 'all'}:${ctx.episode || 'all'}`;
}

function getProviderCacheKey(providerName, ctx) {
  return `${providerName}:${ctx.type}:${ctx.tmdbId}:${ctx.season || 'all'}:${ctx.episode || 'all'}`;
}

function getProviderErrorCacheKey(providerName, ctx) {
  return `err:${providerName}:${ctx.type}:${ctx.tmdbId}:${ctx.season || 'all'}:${ctx.episode || 'all'}`;
}

// ============================================================================
// DEDUPLICATION & CACHING
// ============================================================================

/**
 * Deduplicate concurrent requests for the same content
 * Also checks result cache for recent successful responses
 */
async function deduplicateProviderCall(key, factory, logger) {
  // Check in-flight deduplication cache
  const existing = requestCache.get(key);
  if (existing) {
    metrics.deduplicationHits++;
    logger?.cacheEvent('deduplication_hit', key);
    return existing.promise;
  }

  // Check result cache for completed successful requests
  const resultCacheEntry = providerResultCache.get(key);
  if (resultCacheEntry) {
    metrics.cacheHits++;
    logger?.cacheEvent('result_cache_hit', key, { ageMs: Date.now() - resultCacheEntry.timestamp });
    return Promise.resolve({
      streams: resultCacheEntry.data,
      providerTimings: resultCacheEntry.providerTimings || {},
      providerErrors: [],
      duplicatesRemoved: 0,
      fromCache: true
    });
  }

  metrics.cacheMisses++;
  logger?.cacheEvent('result_cache_miss', key);

  // Create new promise with cleanup
  let resolveRef, rejectRef;
  const promise = new Promise((resolve, reject) => {
    resolveRef = resolve;
    rejectRef = reject;
  }).finally(() => {
    // Clean up after a short delay to allow other callers to get the result
    setTimeout(() => requestCache.delete(key), 1000);
  });

  const entry = { promise, timestamp: Date.now(), resolve: resolveRef, reject: rejectRef };
  requestCache.set(key, entry);

  try {
    const result = await factory();
    // Store in result cache on success
    if (result && result.streams && result.streams.length > 0) {
      providerResultCache.set(key, {
        data: result.streams,
        providerTimings: result.providerTimings,
        timestamp: Date.now()
      });
      logger?.cacheEvent('result_cache_store', key);
    }
    resolveRef(result);
    return result;
  } catch (error) {
    rejectRef(error);
    throw error;
  }
}

/**
 * Execute a provider call with timeout, concurrency limit, and circuit breaker
 */
async function executeProviderWithLimits(providerName, providerFetch, ctx, logger) {
  const timeout = PROVIDER_TIMEOUTS[providerName] || PROVIDER_TIMEOUTS.default;
  const requestId = generateRequestId();

  const logContext = { requestId, provider: providerName, tmdbId: ctx.tmdbId, type: ctx.type };
  const providerLogger = createLogger(logContext);

  // Check circuit breaker
  if (isCircuitOpen(providerName)) {
    providerLogger.warn('Circuit breaker open, skipping provider');
    metrics.providerFailures++;
    return { success: false, data: [], duration: 0, error: 'Circuit breaker open', fromCircuitBreaker: true };
  }

  providerLogger.stageStart('fetch');

  // Wrap the fetch in concurrency limiter and timeout
  const limitedFetch = providerLimiter(async () => {
    return Promise.race([
      providerFetch(ctx),
      new Promise((_, reject) =>
        setTimeout(() => reject(new Error(`Provider timeout after ${timeout}ms`)), timeout)
      )
    ]);
  });

  const t0 = Date.now();
  try {
    const result = await limitedFetch;
    const duration = Date.now() - t0;
    recordSuccess(providerName);
    metrics.providerCalls++;
    metrics.providerSuccesses++;
    metrics.totalDurationMs += duration;

    providerLogger.stageEnd('fetch', duration, 'success', { streamCount: Array.isArray(result) ? result.length : 0 });
    return { success: true, data: result, duration, error: null };
  } catch (error) {
    const duration = Date.now() - t0;
    recordFailure(providerName);
    metrics.providerCalls++;
    metrics.providerFailures++;
    metrics.totalDurationMs += duration;

    if (error.message.includes('timeout')) {
      metrics.providerTimeouts++;
      providerLogger.stageEnd('fetch', duration, 'timeout', { error: error.message });
    } else {
      providerLogger.stageEnd('fetch', duration, 'failed', { error: error.message });
    }

    return { success: false, data: [], duration, error: error.message };
  }
}

// ============================================================================
// AGGREGATION
// ============================================================================

/**
 * Aggregate streams from multiple providers with deduplication, concurrency control, timeout, and caching
 */
async function aggregateProviderStreams(providers, ctx, logger) {
  const requestId = ctx.requestId || generateRequestId();
  const aggLogger = createLogger({ requestId, type: ctx.type, tmdbId: ctx.tmdbId });

  // Create cache key for deduplication
  const cacheKey = getRequestCacheKey(ctx);

  // Use deduplication wrapper (checks in-flight + result cache)
  return deduplicateProviderCall(cacheKey, async () => {
    aggLogger.stageStart('aggregation', { providerCount: providers.length });

    // Execute all providers concurrently with limits
    const providerPromises = providers.map(prov =>
      executeProviderWithLimits(prov.name, prov.fetch, ctx, aggLogger)
    );

    const results = await Promise.all(providerPromises);

    const providerTimings = {};
    const allStreams = [];
    const providerErrors = [];

    for (let i = 0; i < results.length; i++) {
      const { success, data, duration, error, fromCircuitBreaker } = results[i];
      const providerName = providers[i]?.name || 'unknown';

      if (success) {
        // Get provider name from first stream if available, otherwise use the provider's name
        const streamProvider = (data && data.length > 0 && data[0].provider) ? data[0].provider : providerName;
        providerTimings[streamProvider] = duration;
        allStreams.push(...data);
      } else {
        providerTimings[providerName] = duration;
        if (!fromCircuitBreaker) {
          providerErrors.push({ provider: providerName, error, duration });
        }
      }
    }

    // Deduplicate streams by URL (case-insensitive)
    const seenUrls = new Set();
    const uniqueStreams = [];
    let duplicatesRemoved = 0;

    for (const stream of allStreams) {
      if (stream && stream.url) {
        const normalizedUrl = stream.url.toLowerCase();
        if (!seenUrls.has(normalizedUrl)) {
          seenUrls.add(normalizedUrl);
          uniqueStreams.push(stream);
        } else {
          duplicatesRemoved++;
        }
      } else {
        uniqueStreams.push(stream);
      }
    }

    if (duplicatesRemoved > 0) {
      aggLogger.info('Removed duplicate streams', { duplicatesRemoved, finalCount: uniqueStreams.length });
    }

    const totalDuration = Date.now() - (ctx._aggStartTime || Date.now());
    aggLogger.stageEnd('aggregation', totalDuration, 'success', {
      totalStreams: allStreams.length,
      uniqueStreams: uniqueStreams.length,
      duplicatesRemoved,
      providerErrors: providerErrors.length,
      providerTimings
    });

    return {
      streams: uniqueStreams,
      providerTimings,
      providerErrors,
      duplicatesRemoved
    };
  }, aggLogger);
}

/**
 * Execute a single provider with timeout, concurrency limit, and caching
 */
async function executeSingleProvider(provider, ctx, logger) {
  const requestId = ctx.requestId || generateRequestId();
  const providerLogger = createLogger({ requestId, provider: provider.name, tmdbId: ctx.tmdbId, type: ctx.type });

  // Create cache key for deduplication
  const cacheKey = getProviderCacheKey(provider.name, ctx);

  // Use deduplication wrapper
  return deduplicateProviderCall(cacheKey, async () => {
    const result = await executeProviderWithLimits(provider.name, provider.fetch, ctx, providerLogger);

    if (!result.success) {
      return {
        success: false,
        error: result.error,
        streams: [],
        providerTimings: { [provider.name]: result.duration }
      };
    }

    // Store in provider-specific result cache
    providerResultCache.set(cacheKey, {
      data: result.data,
      providerTimings: { [provider.name]: result.duration },
      timestamp: Date.now()
    });

    return {
      success: true,
      streams: result.data,
      providerTimings: { [provider.name]: result.duration }
    };
  }, providerLogger);
}

// ============================================================================
// METRICS EXPORT
// ============================================================================

function getMetrics() {
  return {
    ...metrics,
    cacheHitRate: metrics.cacheHits + metrics.cacheMisses > 0
      ? (metrics.cacheHits / (metrics.cacheHits + metrics.cacheMisses) * 100).toFixed(2) + '%'
      : '0%',
    deduplicationRate: metrics.providerCalls > 0
      ? (metrics.deduplicationHits / metrics.providerCalls * 100).toFixed(2) + '%'
      : '0%',
    avgProviderDurationMs: metrics.providerCalls > 0
      ? Math.round(metrics.totalDurationMs / metrics.providerCalls)
      : 0,
    circuitBreakers: Object.fromEntries(
      Array.from(circuitBreakers.entries()).map(([name, cb]) => [name, {
        state: cb.state,
        failures: cb.failures,
        successes: cb.successes
      }])
    ),
    cacheSizes: {
      inFlight: requestCache.size,
      results: providerResultCache.size,
      errors: providerErrorCache.size
    }
  };
}

function resetMetrics() {
  metrics.deduplicationHits = 0;
  metrics.cacheHits = 0;
  metrics.cacheMisses = 0;
  metrics.providerCalls = 0;
  metrics.providerSuccesses = 0;
  metrics.providerFailures = 0;
  metrics.providerTimeouts = 0;
  metrics.circuitBreakerOpens = 0;
  metrics.totalDurationMs = 0;
  metrics.validationCalls = 0;
  metrics.validationCacheHits = 0;
}

module.exports = {
  aggregateProviderStreams,
  executeSingleProvider,
  getCircuitBreaker,
  recordSuccess,
  recordFailure,
  isCircuitOpen,
  createLogger,
  generateRequestId,
  deduplicateProviderCall,
  providerLimiter,
  PROVIDER_CONCURRENCY_LIMIT,
  PROVIDER_TIMEOUTS,
  logStructured,
  getMetrics,
  resetMetrics
};