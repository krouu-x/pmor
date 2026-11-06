const { config } = require('../utils/config');
const fs = require('fs');
const path = require('path');
const { logStructured } = require('../utils/requestManager');

// Lazy load cache for providers
const providerCache = new Map();

// Function name mappings for existing providers
const providerFunctionMap = {
  'Showbox.js': 'getStreamsFromTmdbId',
  '4khdhub.js': 'get4KHDHubStreams',
  'vixsrc.js': 'getVixsrcStreams',
  'videasy.js': 'getVideasyStreams',
  'vidlink.js': 'getVidlinkStreams',
  'dahmermovies.js': 'getDahmermoviesStreams',
  'streamflix.js': 'getStreamflixStreams',
  'vaplayer.js': 'getVaplayerStreams',
  'castletv.js': 'getCastletvStreams',
  'hdghartv.js': 'getHdghartvStreams',
  'netmirror.js': 'getNetmirrorStreams',
  'onetouchtv.js': 'getOnetouchtvStreams',
  'zxcstreams.js': 'getZxcstreamsStreams',
};

// Stats for debug endpoint
let lastCookieStats = { selected: null, index: null, total: 0, remainingMB: null, timestamp: null };

async function getEffectiveCookies() {
  return Array.isArray(config.febboxCookies) ? config.febboxCookies : [];
}

// Get all provider files
function getProviderFiles() {
  const providersDir = path.join(__dirname);
  return fs.readdirSync(providersDir)
    .filter(file => file.endsWith('.js') && file !== 'registry.js')
    .map(file => ({
      name: path.parse(file).name.toLowerCase(),
      file: file,
      functionName: providerFunctionMap[file]
    }));
}

// Load a provider module
function loadProvider(providerFile) {
  if (!providerCache.has(providerFile)) {
    try {
      providerCache.set(providerFile, require(path.join(__dirname, providerFile)));
    } catch (e) {
      console.error(`Failed to load provider ${providerFile}:`, e.message);
      return null;
    }
  }
  return providerCache.get(providerFile);
}

// Create fetch function for a provider
function createFetchFunction(providerInfo) {
  return async function(ctx) {
    const module = loadProvider(providerInfo.file);
    if (!module) return [];

    const funcName = providerInfo.functionName;
    if (!module[funcName]) {
      logStructured('error', `Provider does not export function`, {
        provider: providerInfo.name,
        stage: 'init',
        requestId: ctx.requestId || 'none',
        tmdbId: ctx.tmdbId || 'none',
        type: ctx.type || 'none',
        error: `Missing function: ${funcName}`
      });
      return [];
    }

    const t0 = Date.now();
    const requestId = ctx.requestId || 'none';

    try {
      const mediaType = ctx.type === 'movie' ? 'movie' : 'tv';

      let result;
      if (providerInfo.name === 'showbox') {
        // Special case for Showbox with TMDB key and cookies
        const { getTmdbApiKey } = require('../utils/tmdbKey');
        const tmdbApiKey = getTmdbApiKey();
        if (!tmdbApiKey) {
          logStructured('warn', 'Showbox skipped: TMDB API key missing', {
            provider: 'showbox',
            stage: 'init',
            requestId,
            tmdbId: ctx.tmdbId,
            type: ctx.type
          });
          return [];
        }
        const cookies = await getEffectiveCookies();
        const previousConfig = global.currentRequestConfig;
        global.currentRequestConfig = { ...(previousConfig || {}) };
        let selected = null;
        if (cookies.length > 0) {
          const index = Math.floor(Math.random() * cookies.length);
          selected = cookies[index];
          global.currentRequestConfig.cookie = selected.startsWith('ui=') ? selected : `ui=${selected}`;
          global.currentRequestConfig.cookies = cookies.map(c => c.startsWith('ui=') ? c : `ui=${c}`);
          lastCookieStats = { selected: selected.slice(0, 16) + '...', index, total: cookies.length, remainingMB: null, timestamp: Date.now() };
          logStructured('info', 'Cookie random pick', {
            provider: 'showbox',
            stage: 'cookie_selection',
            requestId,
            index,
            total: cookies.length
          });
        }
        result = await module[funcName](mediaType, ctx.tmdbId, ctx.season || null, ctx.episode || null, null, selected);
        if (global.currentRequestUserCookieRemainingMB != null) {
          lastCookieStats.remainingMB = global.currentRequestUserCookieRemainingMB;
        }
        global.currentRequestConfig = previousConfig || {};
      } else {
        // Standard provider call - pass requestId if available
        if (ctx.requestId) {
          result = await module[funcName](ctx.tmdbId, mediaType, ctx.season || null, ctx.episode || null, ctx.requestId);
        } else {
          result = await module[funcName](ctx.tmdbId, mediaType, ctx.season || null, ctx.episode || null);
        }
      }

      const durationMs = Date.now() - t0;

      logStructured('info', 'Provider fetch completed', {
        provider: providerInfo.name,
        stage: 'fetch',
        requestId,
        tmdbId: ctx.tmdbId,
        type: ctx.type,
        durationMs,
        streamCount: Array.isArray(result) ? result.length : 0,
        status: 'success'
      });

      if (!Array.isArray(result)) return [];

      // Add provider name if not present
      return result.map(s => ({ ...s, provider: s.provider || providerInfo.name }));

    } catch (e) {
      const durationMs = Date.now() - t0;
      logStructured('error', 'Provider fetch failed', {
        provider: providerInfo.name,
        stage: 'fetch',
        requestId,
        tmdbId: ctx.tmdbId,
        type: ctx.type,
        durationMs,
        error: e.message,
        status: 'failed'
      });
      return [];
    }
  };
}

// Initialize providers - always load all; enabled state is checked dynamically from live config
const providerFiles = getProviderFiles();
const providers = [];

for (const providerInfo of providerFiles) {
  providers.push({
    name: providerInfo.name,
    fetch: createFetchFunction(providerInfo)
  });
  console.log(`[registry] ${providerInfo.name} provider loaded`);
}

function isProviderEnabled(name) {
  const flag = `enable${name.charAt(0).toUpperCase() + name.slice(1)}Provider`;
  return config[flag] !== false;
}

function listProviders() { return providers.map(p => ({ name: p.name, enabled: isProviderEnabled(p.name) })); }
function getProvider(name) {
  const p = providers.find(p => p.name === name.toLowerCase());
  if (!p) return null;
  return { ...p, enabled: isProviderEnabled(p.name) };
}

function getCookieStats() { return lastCookieStats; }

module.exports = { listProviders, getProvider, getCookieStats };
