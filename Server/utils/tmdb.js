const fetch = (...args) => import('node-fetch').then(m => m.default(...args));
const { getTmdbApiKey } = require('./tmdbKey');
const { createLogger, generateRequestId, logStructured } = require('./requestManager');

// ============================================================================
// CACHE CONFIGURATION
// ============================================================================

const CACHE_CONFIG = {
  // Short TTL for dynamic data (external IDs, details)
  shortTtlMs: 6 * 60 * 60 * 1000,      // 6 hours
  // Long TTL for static metadata (images, alternative titles)
  longTtlMs: 24 * 60 * 60 * 1000,      // 24 hours
  // Very short TTL for failed requests to allow quick retry
  errorTtlMs: 60 * 1000,               // 1 minute
  // Max cache entries per cache type
  maxEntries: 5000
};

// ============================================================================
// CACHE STATE
// ============================================================================

const cache = {
  imdbByTmdb: new Map(),       // external_ids
  details: new Map(),          // movie/tv details
  alternativeTitles: new Map(),// alternative titles
  images: new Map(),           // images
  search: new Map(),           // search results (if needed)
  errors: new Map()            // failed requests cache
};

// Cache metrics
const cacheMetrics = {
  hits: { imdbByTmdb: 0, details: 0, alternativeTitles: 0, images: 0, search: 0 },
  misses: { imdbByTmdb: 0, details: 0, alternativeTitles: 0, images: 0, search: 0 },
  errors: { imdbByTmdb: 0, details: 0, alternativeTitles: 0, images: 0, search: 0 },
  evictions: 0
};

function isFresh(entry, ttl = CACHE_CONFIG.shortTtlMs) {
  return entry && (Date.now() - entry.ts) < ttl;
}

function getCacheKey(type, tmdbId, suffix = '') {
  return `${type}:${tmdbId}${suffix ? ':' + suffix : ''}`;
}

function setCacheEntry(cacheMap, key, data, ttl) {
  // Enforce max entries
  if (cacheMap.size >= CACHE_CONFIG.maxEntries) {
    // Remove oldest entry
    const firstKey = cacheMap.keys().next().value;
    if (firstKey) {
      cacheMap.delete(firstKey);
      cacheMetrics.evictions++;
    }
  }
  cacheMap.set(key, { data, ts: Date.now(), ttl });
}

function getCacheEntry(cacheMap, key, ttl) {
  const entry = cacheMap.get(key);
  if (!entry) return null;
  if (!isFresh(entry, entry.ttl || ttl)) {
    cacheMap.delete(key);
    return null;
  }
  return entry;
}

// Periodic cleanup
setInterval(() => {
  const now = Date.now();
  for (const [key, entry] of cache.imdbByTmdb.entries()) {
    if (now - entry.ts > CACHE_CONFIG.shortTtlMs) cache.imdbByTmdb.delete(key);
  }
  for (const [key, entry] of cache.details.entries()) {
    if (now - entry.ts > CACHE_CONFIG.shortTtlMs) cache.details.delete(key);
  }
  for (const [key, entry] of cache.alternativeTitles.entries()) {
    if (now - entry.ts > CACHE_CONFIG.longTtlMs) cache.alternativeTitles.delete(key);
  }
  for (const [key, entry] of cache.images.entries()) {
    if (now - entry.ts > CACHE_CONFIG.longTtlMs) cache.images.delete(key);
  }
  for (const [key, entry] of cache.search.entries()) {
    if (now - entry.ts > CACHE_CONFIG.shortTtlMs) cache.search.delete(key);
  }
  for (const [key, entry] of cache.errors.entries()) {
    if (now - entry.ts > CACHE_CONFIG.errorTtlMs) cache.errors.delete(key);
  }
}, 5 * 60 * 1000).unref();

// ============================================================================
// TMDB FETCH
// ============================================================================

async function tmdbFetchJson(url, logger, cacheType = null, cacheKey = null) {
  const apiKey = getTmdbApiKey();
  if (!apiKey) throw new Error('TMDB_API_KEY missing');
  const sep = url.includes('?') ? '&' : '?';
  const full = `${url}${sep}api_key=${apiKey}`;
  const t0 = Date.now();

  try {
    const res = await fetch(full, { timeout: 15000 });
    const duration = Date.now() - t0;
    if (!res.ok) {
      logger?.warn('TMDB request failed', { url: sanitizeUrl(full), status: res.status, duration });
      throw new Error(`TMDB request failed ${res.status}`);
    }
    const data = await res.json();
    logger?.debug('TMDB request succeeded', { url: sanitizeUrl(full), duration });
    return data;
  } catch (error) {
    const duration = Date.now() - t0;
    logger?.error('TMDB request error', { url: sanitizeUrl(full), duration, error: error.message });

    // Cache errors briefly to prevent hammering on repeated failures
    if (cacheType && cacheKey) {
      cache.errors.set(cacheKey, { error: error.message, ts: Date.now() });
    }

    throw error;
  }
}

function sanitizeUrl(url) {
  try {
    const u = new URL(url);
    u.searchParams.forEach((v, k) => {
      if (k === 'api_key') u.searchParams.set(k, '[REDACTED]');
    });
    return u.toString();
  } catch {
    return '[INVALID_URL]';
  }
}

// ============================================================================
// EXTERNAL IDs (IMDB ID resolution)
// ============================================================================

async function getExternalIds(type, tmdbId, requestId) {
  const logger = createLogger({ requestId, type: 'tmdb', operation: 'externalIds', tmdbId });
  const key = getCacheKey(type, tmdbId);

  // Check error cache first
  const errorEntry = cache.errors.get(key);
  if (errorEntry && Date.now() - errorEntry.ts < CACHE_CONFIG.errorTtlMs) {
    logger.debug('TMDB externalIds error cache hit');
    cacheMetrics.errors.imdbByTmdb++;
    throw new Error(errorEntry.error);
  }

  const cached = getCacheEntry(cache.imdbByTmdb, key, CACHE_CONFIG.shortTtlMs);
  if (cached) {
    logger.debug('TMDB externalIds cache hit');
    cacheMetrics.hits.imdbByTmdb++;
    return cached.data;
  }

  logger.debug('TMDB externalIds cache miss, fetching');
  cacheMetrics.misses.imdbByTmdb++;

  const json = await tmdbFetchJson(`https://api.themoviedb.org/3/${type}/${tmdbId}/external_ids`, logger, 'imdbByTmdb', key);
  setCacheEntry(cache.imdbByTmdb, key, json, CACHE_CONFIG.shortTtlMs);
  return json;
}

// ============================================================================
// DETAILS (movie/tv metadata)
// ============================================================================

async function getDetails(type, tmdbId, requestId) {
  const logger = createLogger({ requestId, type: 'tmdb', operation: 'details', tmdbId });
  const key = getCacheKey(type, tmdbId, 'details');

  const errorEntry = cache.errors.get(key);
  if (errorEntry && Date.now() - errorEntry.ts < CACHE_CONFIG.errorTtlMs) {
    logger.debug('TMDB details error cache hit');
    cacheMetrics.errors.details++;
    throw new Error(errorEntry.error);
  }

  const cached = getCacheEntry(cache.details, key, CACHE_CONFIG.shortTtlMs);
  if (cached) {
    logger.debug('TMDB details cache hit');
    cacheMetrics.hits.details++;
    return cached.data;
  }

  logger.debug('TMDB details cache miss, fetching');
  cacheMetrics.misses.details++;

  const json = await tmdbFetchJson(`https://api.themoviedb.org/3/${type}/${tmdbId}`, logger, 'details', key);
  setCacheEntry(cache.details, key, json, CACHE_CONFIG.shortTtlMs);
  return json;
}

// ============================================================================
// ALTERNATIVE TITLES (static metadata, long TTL)
// ============================================================================

async function getAlternativeTitles(type, tmdbId, requestId) {
  const logger = createLogger({ requestId, type: 'tmdb', operation: 'alternativeTitles', tmdbId });
  const key = getCacheKey(type, tmdbId, 'altTitles');

  const errorEntry = cache.errors.get(key);
  if (errorEntry && Date.now() - errorEntry.ts < CACHE_CONFIG.errorTtlMs) {
    logger.debug('TMDB alternativeTitles error cache hit');
    cacheMetrics.errors.alternativeTitles++;
    throw new Error(errorEntry.error);
  }

  const cached = getCacheEntry(cache.alternativeTitles, key, CACHE_CONFIG.longTtlMs);
  if (cached) {
    logger.debug('TMDB alternativeTitles cache hit');
    cacheMetrics.hits.alternativeTitles++;
    return cached.data;
  }

  logger.debug('TMDB alternativeTitles cache miss, fetching');
  cacheMetrics.misses.alternativeTitles++;

  const json = await tmdbFetchJson(`https://api.themoviedb.org/3/${type}/${tmdbId}/alternative_titles`, logger, 'alternativeTitles', key);
  setCacheEntry(cache.alternativeTitles, key, json, CACHE_CONFIG.longTtlMs);
  return json;
}

// ============================================================================
// IMAGES (static metadata, long TTL)
// ============================================================================

async function getImages(type, tmdbId, requestId) {
  const logger = createLogger({ requestId, type: 'tmdb', operation: 'images', tmdbId });
  const key = getCacheKey(type, tmdbId, 'images');

  const errorEntry = cache.errors.get(key);
  if (errorEntry && Date.now() - errorEntry.ts < CACHE_CONFIG.errorTtlMs) {
    logger.debug('TMDB images error cache hit');
    cacheMetrics.errors.images++;
    throw new Error(errorEntry.error);
  }

  const cached = getCacheEntry(cache.images, key, CACHE_CONFIG.longTtlMs);
  if (cached) {
    logger.debug('TMDB images cache hit');
    cacheMetrics.hits.images++;
    return cached.data;
  }

  logger.debug('TMDB images cache miss, fetching');
  cacheMetrics.misses.images++;

  const json = await tmdbFetchJson(`https://api.themoviedb.org/3/${type}/${tmdbId}/images`, logger, 'images', key);
  setCacheEntry(cache.images, key, json, CACHE_CONFIG.longTtlMs);
  return json;
}

// ============================================================================
// RESOLVE IMDB ID
// ============================================================================

async function resolveImdbId(type, tmdbId, requestId) {
  const logger = createLogger({ requestId, type: 'tmdb', operation: 'resolveImdbId', tmdbId });
  try {
    const ext = await getExternalIds(type, tmdbId, requestId);
    const imdbId = ext.imdb_id || null;
    if (imdbId) {
      logger.info('Resolved IMDB ID', { imdbId });
    } else {
      logger.warn('No IMDB ID found');
    }
    return imdbId;
  } catch (error) {
    logger.error('Failed to resolve IMDB ID', { error: error.message });
    return null;
  }
}

// ============================================================================
// CACHE METRICS
// ============================================================================

function getCacheMetrics() {
  const totalHits = Object.values(cacheMetrics.hits).reduce((a, b) => a + b, 0);
  const totalMisses = Object.values(cacheMetrics.misses).reduce((a, b) => a + b, 0);
  const totalErrors = Object.values(cacheMetrics.errors).reduce((a, b) => a + b, 0);
  const total = totalHits + totalMisses;

  return {
    hits: cacheMetrics.hits,
    misses: cacheMetrics.misses,
    errors: cacheMetrics.errors,
    evictions: cacheMetrics.evictions,
    totalHits,
    totalMisses,
    totalErrors,
    hitRate: total > 0 ? ((totalHits / total) * 100).toFixed(2) + '%' : '0%',
    cacheSizes: {
      imdbByTmdb: cache.imdbByTmdb.size,
      details: cache.details.size,
      alternativeTitles: cache.alternativeTitles.size,
      images: cache.images.size,
      search: cache.search.size,
      errors: cache.errors.size
    }
  };
}

function resetCacheMetrics() {
  cacheMetrics.hits = { imdbByTmdb: 0, details: 0, alternativeTitles: 0, images: 0, search: 0 };
  cacheMetrics.misses = { imdbByTmdb: 0, details: 0, alternativeTitles: 0, images: 0, search: 0 };
  cacheMetrics.errors = { imdbByTmdb: 0, details: 0, alternativeTitles: 0, images: 0, search: 0 };
  cacheMetrics.evictions = 0;
}

module.exports = {
  getExternalIds,
  getDetails,
  getAlternativeTitles,
  getImages,
  resolveImdbId,
  getCacheMetrics,
  resetCacheMetrics,
  cache // Export for testing/debugging
};