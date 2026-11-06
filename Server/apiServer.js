require('dotenv').config();
const express = require('express');
const cors = require('cors');
const os = require('os');
const { config, saveConfigPatch, OVERRIDE_PATH } = require('./utils/config');
const { authenticate, issueSession, requireAuth, getSession, updatePassword } = require('./utils/auth');
const path = require('path');
const { listProviders, getProvider, getCookieStats } = require('./providers/registry');
const { createProxyRoutes, processStreamsForProxy } = require('./proxy/proxyServer');
const { resolveImdbId, getTrailer, getCacheMetrics: getTmdbCacheMetrics } = require('./utils/tmdb');
const { applyFilters } = require('./utils/streamFilters');
const { aggregateProviderStreams, executeSingleProvider, createLogger, generateRequestId, getMetrics: getRequestMetrics } = require('./utils/requestManager');

const app = express();
app.set('trust proxy', 1);

// Conditionally mount proxy routes early so downstream handlers can use them
if (config.enableProxy) {
  console.log('[startup] enableProxy flag active: mounting proxy routes');
  createProxyRoutes(app);
} else {
  console.log('[startup] enableProxy flag disabled: proxy routes not mounted');
}

// --- Simple In-Memory Rate Limiting for /auth/login ---
const loginAttempts = new Map(); // key: ip, value: { count, first, last, lockedUntil }
const MAX_ATTEMPTS_WINDOW = 5; // attempts allowed
const WINDOW_MS = 10 * 60 * 1000; // 10 minutes window
const BASE_LOCK_MS = 5 * 60 * 1000; // 5 minutes base lock

function getClientIp(req){
  return (req.headers['x-forwarded-for'] || req.connection.remoteAddress || '').split(',')[0].trim();
}

function recordLoginFailure(ip){
  const now = Date.now();
  let entry = loginAttempts.get(ip);
  if (!entry) {
    entry = { count:1, first: now, last: now, lockedUntil:0 };
    loginAttempts.set(ip, entry);
    return entry;
  }
  // Reset window if outside timeframe and not locked
  if (now - entry.first > WINDOW_MS && now > entry.lockedUntil) {
    entry.count = 1;
    entry.first = now;
  } else {
    entry.count++;
  }
  entry.last = now;
  if (entry.count > MAX_ATTEMPTS_WINDOW) {
    // Exponential backoff lock: base * 2^(count - limit)
    const over = entry.count - MAX_ATTEMPTS_WINDOW;
    const lockMs = BASE_LOCK_MS * Math.min(8, Math.pow(2, over-1));
    entry.lockedUntil = now + lockMs;
  }
  return entry;
}

function canAttempt(ip){
  const entry = loginAttempts.get(ip);
  if (!entry) return { allowed:true };
  const now = Date.now();
  if (entry.lockedUntil && now < entry.lockedUntil) {
    return { allowed:false, retryAfter: Math.ceil((entry.lockedUntil - now)/1000) };
  }
  if (now - entry.first > WINDOW_MS) {
    // Window passed; reset
    loginAttempts.delete(ip);
    return { allowed:true };
  }
  return { allowed:true };
}

function recordLoginSuccess(ip){
  // On success clear state to avoid lingering count
  loginAttempts.delete(ip);
}

// Guard against premature process.exit from imported legacy modules, but allow controlled restarts
const realProcessExit = process.exit.bind(process);
let allowControlledExit = false;
process.exit = function(code){
  if (allowControlledExit) return realProcessExit(code);
  console.warn('[diagnostic] Intercepted process.exit with code', code, new Error('exit trace').stack);
  // keep process alive for debugging
};
setImmediate(()=>console.log('[diagnostic] post-start setImmediate fired'));
app.use(cors());
app.use(express.json());

// --- Auth Routes (login before static serving) ---
app.post('/auth/login', (req,res) => {
  const { username, password } = req.body || {};
  const ip = getClientIp(req);
  const attemptState = canAttempt(ip);
  if (!attemptState.allowed) {
    res.setHeader('Retry-After', String(attemptState.retryAfter));
    return res.status(429).json({ success:false, error:'TOO_MANY_ATTEMPTS', retryAfter: attemptState.retryAfter });
  }
  if (!username || !password) return res.status(400).json({ success:false, error:'MISSING_CREDENTIALS' });
  if (!authenticate(username, password)) {
    const entry = recordLoginFailure(ip);
    if (entry.lockedUntil && Date.now() < entry.lockedUntil) {
      const retryAfter = Math.ceil((entry.lockedUntil - Date.now())/1000);
      res.setHeader('Retry-After', String(retryAfter));
      return res.status(429).json({ success:false, error:'LOCKED', retryAfter });
    }
    return res.status(401).json({ success:false, error:'INVALID_CREDENTIALS', remaining: Math.max(0, MAX_ATTEMPTS_WINDOW - entry.count) });
  }
  recordLoginSuccess(ip);
  const token = issueSession(username);
  res.setHeader('Set-Cookie', `session=${token}; HttpOnly; SameSite=Lax; Path=/; Max-Age=${12*60*60}`);
  res.json({ success:true, username });
});

app.post('/auth/logout', (req,res) => {
  res.setHeader('Set-Cookie', 'session=; HttpOnly; SameSite=Lax; Path=/; Max-Age=0');
  res.json({ success:true });
});

app.get('/auth/session', (req,res) => {
  const sess = getSession(req);
  if (!sess) return res.json({ authenticated:false });
  res.json({ authenticated:true, username: sess.u });
});

app.post('/auth/change-password', requireAuth, (req,res) => {
  const { oldPassword, newPassword } = req.body || {};
  if (!oldPassword || !newPassword) return res.status(400).json({ success:false, error:'MISSING_FIELDS' });
  const sess = req.session;
  if (!authenticate(sess.u, oldPassword)) return res.status(401).json({ success:false, error:'INVALID_OLD_PASSWORD' });
  if (newPassword.length < 8) return res.status(400).json({ success:false, error:'PASSWORD_TOO_SHORT' });
  if (!updatePassword(sess.u, newPassword)) return res.status(500).json({ success:false, error:'UPDATE_FAILED' });
  res.json({ success:true, message:'PASSWORD_UPDATED' });
});

// Protect config panel (HTML) explicitly before static middleware
app.get('/config.html', (req,res,next) => {
  const sess = getSession(req);
  if (!sess) return res.redirect(302, '/');
  res.setHeader('Cache-Control','no-store, must-revalidate');
  res.setHeader('Pragma','no-cache');
  res.setHeader('Expires','0');
  res.sendFile(path.join(process.cwd(),'public','config.html'));
});

// Explicit root handler for login page to ensure no-store
app.get('/', (req,res) => {
  res.setHeader('Cache-Control','no-store, must-revalidate');
  res.setHeader('Pragma','no-cache');
  res.setHeader('Expires','0');
  res.sendFile(path.join(process.cwd(),'public','index.html'));
});

// Diagnostics for unexpected exits
process.on('beforeExit', (code) => {
  console.log('[diagnostic] beforeExit code=', code);
});
process.on('exit', (code) => {
  console.log('[diagnostic] exit code=', code);
});
process.on('uncaughtException', (err) => {
  console.error('[diagnostic] uncaughtException', err);
});
process.on('unhandledRejection', (reason) => {
  console.error('[diagnostic] unhandledRejection', reason);
});
// Periodic heartbeat to confirm event loop activity (can be removed later)
let hbCount = 0;
setInterval(()=>{
  hbCount++;
  if (hbCount % 6 === 0) { // every 60s if interval is 10s
    console.log('[diagnostic] heartbeat 60s elapsed, process alive');
  }
}, 10_000).unref();


// --- Metrics (in-memory) ---
const metrics = {
  startTime: Date.now(),
  requestsTotal: 0,
  streamRequests: 0,
  providerCalls: {},
  lastRequestAt: null,
  lastError: null,
  streamsReturned: 0,
  tmdbToImdbLookups: 0,
  errorsTotal: 0,
  rateLimited: 0,
  cacheHits: 0,
  cacheMisses: 0,
  avgLatencyMs: 0,
  latencySum: 0,
  latencyCount: 0
};

// Service metrics for /api/status
let serviceMetrics = {
  cacheEntries: 0,
  tmdbReachable: true
};

// --- Middleware to track metrics ---
app.use((req,res,next)=>{
  metrics.requestsTotal++;
  metrics.lastRequestAt = Date.now();

  // Track latency
  const start = process.hrtime.bigint();
  res.on('finish', () => {
    const end = process.hrtime.bigint();
    const latencyMs = Number(end - start) / 1e6;
    metrics.latencySum += latencyMs;
    metrics.latencyCount++;
    metrics.avgLatencyMs = metrics.latencySum / metrics.latencyCount;

    // Track errors
    if (res.statusCode >= 400) {
      metrics.errorsTotal++;
    }
    if (res.statusCode === 429) {
      metrics.rateLimited++;
    }
  });
  next();
});
// Serve static UI (login page at /)
app.use(express.static(path.join(process.cwd(),'public')));

// --- Helper: constant-time token compare ---
function verifyServiceToken(req) {
  const token = process.env.SERVICE_TOKEN;
  if (!token) return false; // No token configured, deny access
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) return false;
  const providedToken = authHeader.substring(7);
  // Constant-time comparison
  if (providedToken.length !== token.length) return false;
  let result = 0;
  for (let i = 0; i < token.length; i++) {
    result |= providedToken.charCodeAt(i) ^ token.charCodeAt(i);
  }
  return result === 0;
}

// --- Service API Routes (ABOVE /tmdb/ handler) ---

// Health endpoint - public
app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', time: new Date().toISOString() });
});

// Status endpoint - protected by bearer token
app.get('/api/status', (req, res) => {
  if (!verifyServiceToken(req)) {
    return res.status(401).json({ success: false, error: 'Not authorized' });
  }
  res.json({
    version: '1.0.0',
    uptimeSeconds: Math.round((Date.now() - metrics.startTime) / 1000),
    cacheEntries: serviceMetrics.cacheEntries,
    tmdbReachable: serviceMetrics.tmdbReachable
  });
});

// Metrics endpoint - protected by bearer token
app.get('/api/metrics', (req, res) => {
  if (!verifyServiceToken(req)) {
    return res.status(401).json({ success: false, error: 'Not authorized' });
  }
  res.json({
    requestsTotal: metrics.requestsTotal,
    errorsTotal: metrics.errorsTotal,
    rateLimited: metrics.rateLimited,
    cacheHits: metrics.cacheHits,
    cacheMisses: metrics.cacheMisses,
    avgLatencyMs: Math.round(metrics.avgLatencyMs * 10) / 10
  });
});

// Detailed metrics endpoint - protected by bearer token
app.get('/api/metrics/detailed', (req, res) => {
  if (!verifyServiceToken(req)) {
    return res.status(401).json({ success: false, error: 'Not authorized' });
  }

  const requestMetrics = getRequestMetrics();
  const tmdbCacheMetrics = getTmdbCacheMetrics();

  res.json({
    // General API metrics
    api: {
      requestsTotal: metrics.requestsTotal,
      errorsTotal: metrics.errorsTotal,
      rateLimited: metrics.rateLimited,
      cacheHits: metrics.cacheHits,
      cacheMisses: metrics.cacheMisses,
      avgLatencyMs: Math.round(metrics.avgLatencyMs * 10) / 10,
      uptimeSeconds: Math.round((Date.now() - metrics.startTime) / 1000)
    },
    // Request manager metrics (provider calls, deduplication, circuit breakers)
    requestManager: requestMetrics,
    // TMDB cache metrics
    tmdbCache: tmdbCacheMetrics,
    // Memory usage
    memoryMB: Math.round(process.memoryUsage().rss / 1024 / 1024),
    // Node.js version
    nodeVersion: process.version
  });
});

// Config API
app.get('/api/config', (req,res) => {
  const fs = require('fs');
  let override = {};
  try { if (fs.existsSync(OVERRIDE_PATH)) override = JSON.parse(fs.readFileSync(OVERRIDE_PATH,'utf8')); } catch (e) {
    // ignore JSON parse or fs errors reading override; return base config
  }
  res.json({ success:true, merged: config, override, overridePath: OVERRIDE_PATH });
});
app.post('/api/config', (req,res) => {
  const patch = req.body || {};
  if (patch.port) {
    const p = Number(patch.port); if (!Number.isFinite(p) || p<=0 || p>65535) return res.status(400).json({ success:false, error:'INVALID_PORT'});
    patch.port = p;
  }
  if (patch.defaultProviders && !Array.isArray(patch.defaultProviders)) return res.status(400).json({ success:false, error:'DEFAULT_PROVIDERS_NOT_ARRAY'});
  const ok = saveConfigPatch(patch);
  res.json({ success: ok, merged: config });
});

// Restart endpoint (requires auth via session cookie on /config.html UI)
app.post('/api/restart', (req,res) => {
  const sess = getSession(req);
  if(!sess) return res.status(401).json({ success:false, error:'UNAUTHORIZED' });
  res.json({ success:true, message:'RESTARTING' });
  // Give the response a moment to flush
  setTimeout(()=>{
    try {
      const fs = require('fs');
      const restartMarker = require('path').join(process.cwd(), 'restart.trigger');
      fs.writeFileSync(restartMarker, String(Date.now()));
      console.warn('[control] wrote restart.trigger to notify nodemon');
    } catch (e) {
      console.warn('[control] failed to write restart marker:', e.message);
    }
    console.warn('[control] restarting process by exit(0)');
    // Let nodemon detect the file change and restart the app
    allowControlledExit = true;
    realProcessExit(0);
  }, 300);
});

// --- Basic informational endpoints ---
app.get('/api/health-old', (req, res) => {
  res.json({ ok: true, service: 'tmdb-embed-api', time: new Date().toISOString() });
});

// Metrics endpoint
app.get('/api/metrics-old', (req,res) => {
  res.json({
    uptimeSeconds: Math.round((Date.now()-metrics.startTime)/1000),
    requestsTotal: metrics.requestsTotal,
    streamRequests: metrics.streamRequests,
    providerCalls: metrics.providerCalls,
    streamsReturned: metrics.streamsReturned,
    tmdbToImdbLookups: metrics.tmdbToImdbLookups,
    lastRequestAt: metrics.lastRequestAt,
    memoryMB: Math.round(process.memoryUsage().rss/1024/1024),
    loadAvg: os.loadavg ? os.loadavg() : [],
    nodeVersion: process.version,
    configDefaults: {
      region: config.defaultRegion,
      providers: config.defaultProviders,
      minQualities: config.minQualities ? Object.keys(config.minQualities).length : 0,
      excludeCodecs: config.excludeCodecs ? Object.keys(config.excludeCodecs).filter(k=>config.excludeCodecs[k]).length : 0,
      febboxCookies: config.febboxCookies.length
    }
  });
});

// Consolidated status (metrics + providers + endpoints)
app.get('/api/status-old', (req,res) => {
  const endpoints = [
    'GET /api/health',
    'GET /api/metrics',
    'GET /api/status',
    'GET /api/providers',
    'GET /api/providers/:name',
    'GET /api/streams/:type/:tmdbId',
    'GET /api/streams/:provider/:type/:tmdbId',
    'POST /api/config',
    'GET /api/config'
  ];
  // Determine cookie requirement heuristically (currently Showbox / PStream)
  const cookieRequiredProviders = new Set(['showbox']);
  const providers = listProviders().map(p => {
    const cookieRequired = cookieRequiredProviders.has(p.name);
    const cookieOk = !cookieRequired || (config.febboxCookies && config.febboxCookies.length > 0);
    return { name: p.name, enabled: p.enabled, cookieRequired, cookieOk };
  });
  res.json({ success:true, providerCheckTmdbId: config.providerCheckTmdbId, metrics: {
    uptimeSeconds: Math.round((Date.now()-metrics.startTime)/1000),
    requestsTotal: metrics.requestsTotal,
    streamRequests: metrics.streamRequests,
    providerCalls: metrics.providerCalls,
    streamsReturned: metrics.streamsReturned,
    tmdbToImdbLookups: metrics.tmdbToImdbLookups,
    lastRequestAt: metrics.lastRequestAt,
    memoryMB: Math.round(process.memoryUsage().rss/1024/1024)
  }, endpoints, providers });
});

// Providers list
app.get('/api/providers', (req,res) => {
  res.json({ success: true, providers: listProviders() });
});

// Debug environment/config endpoint (do not expose publicly in production)
app.get('/api/debug/env', (req,res) => {
  const cookieStats = getCookieStats ? getCookieStats() : null;
  res.json({
    port: config.port,
    defaultProviders: config.defaultProviders,
    febboxCookieCount: config.febboxCookies.length,
    showboxCacheDir: process.env.SHOWBOX_CACHE_DIR || '(os tmp)',
    nodeVersion: process.version,
    cookieStats
  });
});

// Single provider info
app.get('/api/providers/:name', (req,res) => {
  const p = getProvider(req.params.name);
  if (!p) return res.status(404).json({ success:false, error:'PROVIDER_NOT_FOUND' });
  res.json({ success:true, provider:{ name: p.name, enabled: p.enabled } });
});

// Aggregate streams across all enabled providers
app.get('/api/streams/:type/:tmdbId', async (req,res) => {
  const { type, tmdbId } = req.params;
  if (!['movie','series'].includes(type)) return res.status(400).json({ success:false, error:'INVALID_TYPE' });
  const season = req.query.season ? Number(req.query.season) : null;
  const episode = req.query.episode ? Number(req.query.episode) : null;
  try {
    metrics.streamRequests++;
    const selectedProviderNames = (config.defaultProviders.length ? config.defaultProviders : listProviders().map(p=>p.name));
    const selectedProviders = selectedProviderNames.map(name => getProvider(name)).filter(p => p && p.enabled);

    const requestId = generateRequestId();
    const logger = createLogger({ requestId, endpoint: 'aggregate', tmdbId, type });

    const tmdbType = type === 'movie' ? 'movie' : 'tv';
    const imdbId = await resolveImdbId(tmdbType, tmdbId, requestId); if (imdbId) metrics.tmdbToImdbLookups++;

    const ctx = { tmdbId, type, season, episode, imdbId, filters: {}, requestId };

    const { streams, providerTimings, providerErrors, duplicatesRemoved } = await aggregateProviderStreams(selectedProviders, ctx, logger);

    // Update metrics
    for (const prov of selectedProviders) {
      metrics.providerCalls[prov.name] = (metrics.providerCalls[prov.name]||0)+1;
    }
    metrics.streamsReturned += streams.length;

    // Apply filters
    let filteredStreams = applyFilters(streams, 'aggregate', config.minQualities, config.excludeCodecs);

    if (config.enableProxy) {
      const serverUrl = `${req.protocol}://${req.get('host')}`;
      filteredStreams = processStreamsForProxy(filteredStreams, serverUrl);
      // Omit original headers when proxying to avoid leaking upstream requirements
      filteredStreams = filteredStreams.map(s => { if (s && typeof s === 'object') { const { headers, ...rest } = s; return rest; } return s; });
    }

    res.json({
      success: true,
      tmdbId,
      imdbId,
      count: filteredStreams.length,
      providerTimings,
      providerErrors,
      duplicatesRemoved,
      streams: filteredStreams
    });
  } catch (e) {
    metrics.lastError = e.message;
    res.status(500).json({ success:false, error:'INTERNAL_ERROR', message:e.message });
  }
});

// Provider-specific streams
app.get('/api/streams/:provider/:type/:tmdbId', async (req,res) => {
  const { provider, type, tmdbId } = req.params;
  if (!['movie','series'].includes(type)) return res.status(400).json({ success:false, error:'INVALID_TYPE' });
  const season = req.query.season ? Number(req.query.season) : null;
  const episode = req.query.episode ? Number(req.query.episode) : null;
  const prov = getProvider(provider);
  if (!prov) return res.status(404).json({ success:false, error:'PROVIDER_NOT_FOUND' });
  if (!prov.enabled) return res.status(503).json({ success:false, error:'PROVIDER_DISABLED' });
  try {
    metrics.streamRequests++;
    const tmdbType = type === 'movie' ? 'movie' : 'tv';

    const requestId = generateRequestId();
    const imdbId = await resolveImdbId(tmdbType, tmdbId, requestId); if (imdbId) metrics.tmdbToImdbLookups++;

    const logger = createLogger({ requestId, endpoint: 'single', provider: prov.name, tmdbId, type });

    const ctx = { tmdbId, type, season, episode, imdbId, filters: {}, requestId };

    const { success, streams, providerTimings, error } = await executeSingleProvider(prov, ctx, logger);

    if (!success) {
      metrics.providerCalls[prov.name] = (metrics.providerCalls[prov.name]||0)+1;
      return res.status(500).json({ success: false, error: error || 'PROVIDER_ERROR', provider: prov.name });
    }

    metrics.providerCalls[prov.name] = (metrics.providerCalls[prov.name]||0)+1;
    metrics.streamsReturned += streams.length;

    // Apply filters
    let filteredStreams = applyFilters(streams, prov.name, config.minQualities, config.excludeCodecs);

    if (config.enableProxy) {
      const serverUrl = `${req.protocol}://${req.get('host')}`;
      filteredStreams = processStreamsForProxy(filteredStreams, serverUrl);
      filteredStreams = filteredStreams.map(s => { if (s && typeof s === 'object') { const { headers, ...rest } = s; return rest; } return s; });
    }

    res.json({ success: true, provider: prov.name, tmdbId, imdbId, count: filteredStreams.length, providerTimings, streams: filteredStreams });
  } catch (e) {
    metrics.lastError = e.message;
    res.status(500).json({ success:false, error:'INTERNAL_ERROR', message:e.message });
  }
});

// Trailer endpoint
app.get('/api/trailer/:type/:tmdbId', async (req,res) => {
  const { type, tmdbId } = req.params;
  if (!['movie','series'].includes(type)) return res.status(400).json({ success:false, error:'INVALID_TYPE' });
  try {
    const tmdbType = type === 'movie' ? 'movie' : 'tv';
    const trailer = await getTrailer(tmdbType, tmdbId);
    if (!trailer) {
      return res.json({ success:true, tmdbId, trailer: null });
    }
    res.json({
      success: true,
      tmdbId,
      trailer: {
        key: trailer.key,
        name: trailer.name,
        site: trailer.site,
        type: trailer.type,
        official: trailer.official,
        publishedAt: trailer.published_at,
        url: `https://www.youtube.com/watch?v=${trailer.key}`,
        embedUrl: `https://www.youtube.com/embed/${trailer.key}?autoplay=1`
      }
    });
  } catch (e) {
    metrics.lastError = e.message;
    res.status(500).json({ success:false, error:'INTERNAL_ERROR', message:e.message });
  }
});

const PORT = Number(process.env.PORT) || config.port || 8787;
const HOST = process.env.BIND_HOST || '0.0.0.0';
const server = app.listen(PORT, HOST, () => {
  console.log(`TMDB Embed REST API listening on http://${HOST}:${PORT}`);
  console.log('Endpoints:');
  console.log('  GET  /api/health');
  console.log('  GET  /api/status');
  console.log('  GET  /api/metrics');
  console.log('  GET  /api/providers');
  console.log('  GET  /api/streams/:type/:id');
  console.log('  POST /api/streams/:type/:id');
  if (!config.febboxCookies || config.febboxCookies.length === 0) {
    console.warn('[startup][warning] No FEBBOX_COOKIES configured. Showbox / PStream related streams may be unavailable. Set FEBBOX_COOKIES in your environment to enable these sources.');
  }
});

server.on('error', (err) => { console.error('[diagnostic] server error', err); });
