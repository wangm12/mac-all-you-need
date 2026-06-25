importScripts('cookie-sync-domains.js', 'media-patterns.js')
const COOKIE_SYNC_DOMAINS = globalThis.COOKIE_SYNC_DOMAINS
const { MEDIA_PATTERNS, MIN_VIDEO_SIZE, SIZE_EXEMPT_TYPES } = globalThis.MAYNMediaPatterns

const APP_URL = 'http://127.0.0.1:18765'
const COMPANION_WAKE_URL = 'mayn://companion/wake'

async function getAuthToken() {
  const r = await chrome.storage.local.get('maynAuthToken')
  if (r.maynAuthToken) return r.maynAuthToken
  const t = crypto.randomUUID()
  await chrome.storage.local.set({ maynAuthToken: t })
  return t
}
const LAST_DOWNLOAD_ERROR_TTL_MS = 10 * 60 * 1000

// True once this service-worker lifetime has successfully registered its token
// with the app via /ping. Reset on a 401 so we re-register and retry once.
let registeredThisSession = false

/**
 * Idempotent token registration. GETs /ping with X-MAYN-Token and awaits success
 * before any cookie sync or download. Returns { ok, error? }.
 */
async function ensureRegistered(opts = {}) {
  if (registeredThisSession && !opts.force) return { ok: true }
  try {
    const token = await getAuthToken()
    const res = await fetch(`${APP_URL}/ping`, {
      headers: { 'X-MAYN-Token': token }
    })
    if (res.ok) {
      registeredThisSession = true
      return { ok: true }
    }
    if (res.status === 409) {
      logBg('ensure-registered-conflict', { status: res.status })
      await fetch(`${APP_URL}/companion-reset`, { method: 'POST' })
      const retry = await fetch(`${APP_URL}/ping`, {
        headers: { 'X-MAYN-Token': token }
      })
      if (retry.ok) {
        registeredThisSession = true
        return { ok: true }
      }
      return {
        ok: false,
        error: 'Companion token mismatch — click Reset Registration in Downloads settings, reload the extension in chrome://extensions, then sync again.'
      }
    }
    const serverError = await readServerError(res)
    return {
      ok: false,
      error: serverError || 'Mac All You Need did not accept Companion registration (is the app running?)'
    }
  } catch {
    return {
      ok: false,
      error: 'Could not reach Mac All You Need on localhost:18765 (is the app running?)'
    }
  }
}

async function readServerError(res) {
  try {
    const data = await res.clone().json()
    if (!data || typeof data.error !== 'string') return null
    switch (data.error) {
      case 'unauthorized':
        return 'Companion is not authorized — open Downloads settings and click Reset Registration, then sync again.'
      case 'not registered':
        return 'Companion is not registered yet — keep this page open with the extension installed.'
      case 'already registered':
        return 'Companion token mismatch — open Downloads settings and click Reset Registration, then sync again.'
      default:
        return data.error
    }
  } catch {
    return null
  }
}

/**
 * fetch() against the app that guarantees the token is registered first and
 * transparently recovers from a stale-session 401: on 401, clear the session
 * flag, re-register, and retry the request exactly once.
 */
async function authedFetch(path, init = {}) {
  const registration = await ensureRegistered()
  if (!registration.ok) {
    return { ok: false, status: 0, _unregistered: true, _error: registration.error }
  }
  const token = await getAuthToken()
  const withToken = (extra) => ({
    ...init,
    headers: { ...(init.headers || {}), 'X-MAYN-Token': token, ...extra }
  })
  let res = await fetch(`${APP_URL}${path}`, withToken())
  if (res.status === 401) {
    registeredThisSession = false
    const retryRegistration = await ensureRegistered()
    if (!retryRegistration.ok) return res
    res = await fetch(`${APP_URL}${path}`, withToken())
  }
  return res
}

function truncateUrl(u, max = 72) {
  if (!u || typeof u !== 'string') return ''
  return u.length <= max ? u : `${u.slice(0, max)}…`
}

/** Service worker console: chrome://extensions → Mac All You Need Downloader → “service worker” → Inspect */
function logBg(stage, data) {
  const line = { stage, t: new Date().toISOString(), ...data }
  console.info('[MAYN downloader ext]', line)
}

function setLastDownloadError(message) {
  try {
    chrome.storage.local.set({
      lastDownloadError: { message: String(message), t: Date.now() }
    })
  } catch {
    /* ignore */
  }
}

function clearLastDownloadError() {
  try {
    chrome.storage.local.remove('lastDownloadError')
  } catch {
    /* ignore */
  }
}

function isFreshDownloadError(err) {
  if (!err || typeof err.message !== 'string') return false
  const ts = Number(err.t || 0)
  return Number.isFinite(ts) && Date.now() - ts < LAST_DOWNLOAD_ERROR_TTL_MS
}

function cleanupLastDownloadError() {
  try {
    chrome.storage.local.get(['lastDownloadError'], ({ lastDownloadError }) => {
      if (!lastDownloadError) return
      if (!isFreshDownloadError(lastDownloadError)) {
        chrome.storage.local.remove('lastDownloadError')
      }
    })
  } catch {
    /* ignore */
  }
}

const DEBOUNCE_MS = 2000

const ICON_ACTIVE = {
  16: 'icons/icon16.png',
  48: 'icons/icon48.png'
}

const FRAME_BUCKET_MAX = 300

/**
 * Launch Mac All You Need via the registered mayn:// URL scheme when localhost
 * is unreachable (app quit or not yet listening on :18765).
 */
async function launchMacAppForDownload() {
  logBg('launch-mac-app', { wakeURL: COMPANION_WAKE_URL })
  try {
    await chrome.tabs.create({ url: COMPANION_WAKE_URL, active: false })
    return true
  } catch (e) {
    logBg('launch-mac-app-failed', { err: String(e) })
    return false
  }
}

async function postDownloadsQueueWhenReady(requests, maxAttempts = 48, delayMs = 500) {
  const rid = `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 7)}`
  logBg('post-queue-start', {
    rid,
    n: requests.length,
    url0: truncateUrl(requests[0]?.url),
    type0: requests[0]?.type
  })
  let launchedApp = false
  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    try {
      // ensureRegistered() replaces the bare /ping: it registers (first-write-wins)
      // and only resolves true once the app has acknowledged our token.
      const registration = await ensureRegistered()
      if (!registration.ok) {
        if (!launchedApp && requests[0]) {
          launchedApp = await launchMacAppForDownload()
          logBg('post-queue-launched-app', { rid, launchedApp, attempt })
        }
        if (attempt === 0 || attempt % 10 === 0) {
          logBg('post-queue-ping-notok', { rid, attempt, launchedApp })
        }
        await new Promise((r) => setTimeout(r, delayMs))
        continue
      }
      if (registration.ok) {
        logBg('post-queue-ping-ok', { rid, attempt })
        const syncResult = await syncCookies({ forced: true })
        if (!syncResult.ok) throw new Error(syncResult.error || 'cookie sync failed')
        for (let i = 0; i < requests.length; i++) {
          const req = requests[i]
          const res = await authedFetch('/download', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(req)
          })
          logBg('post-queue-download-post', { rid, i, status: res.status, ok: res.ok })
          if (!res.ok) throw new Error(`HTTP ${res.status}`)
        }
        logBg('post-queue-done', { rid, ok: true })
        clearLastDownloadError()
        return true
      }
      if (attempt === 0 || attempt % 10 === 0) {
        logBg('post-queue-ping-notok', { rid, attempt })
      }
    } catch (e) {
      if (attempt === 0 || attempt % 10 === 0) {
        logBg('post-queue-attempt-catch', { rid, attempt, err: String(e) })
      }
    }
    await new Promise((r) => setTimeout(r, delayMs))
  }
  logBg('post-queue-timeout', { rid, maxAttempts, delayMs })
  setLastDownloadError(
    'Mac All You Need did not respond on localhost after several attempts. Open the desktop app and try again.'
  )
  return false
}

function postDownloadWhenAppReady(request) {
  return postDownloadsQueueWhenReady([request])
}

// tabMedia: Map<tabId, Map<frameId, Map<url, mediaEntry>>>
const tabMedia = new Map()

// Persist tabMedia to chrome.storage.session so sniffed media survives SW sleep.
let saveTimer = null
function scheduleTabMediaSave() {
  clearTimeout(saveTimer)
  saveTimer = setTimeout(() => {
    const obj = {}
    for (const [tabId, frames] of tabMedia) {
      const framesObj = {}
      for (const [frameId, bucket] of frames) {
        const bucketObj = {}
        for (const [url, entry] of bucket) bucketObj[url] = entry
        framesObj[String(frameId)] = bucketObj
      }
      obj[String(tabId)] = framesObj
    }
    chrome.storage.session.set({ tabMedia: obj })
  }, 200)
}

// Restore tabMedia on SW wake.
chrome.storage.session.get('tabMedia').then((res) => {
  if (!res.tabMedia) return
  for (const [tabIdStr, framesObj] of Object.entries(res.tabMedia)) {
    const tabId = Number(tabIdStr)
    for (const [frameIdStr, bucketObj] of Object.entries(framesObj)) {
      const frameId = Number(frameIdStr)
      for (const [url, entry] of Object.entries(bucketObj)) {
        // Use the existing helper so cap logic applies on replay too.
        addMediaEntry(tabId, frameId, url, entry)
      }
    }
  }
})

let lastClickTime = 0
let lastWakeBgAt = 0
let lastCookieSyncAt = 0
const WAKE_DEBOUNCE_MS = 2000

// --- Frame-aware storage helpers ---

function getFrameBucket(tabId, frameId) {
  if (!tabMedia.has(tabId)) tabMedia.set(tabId, new Map())
  const tab = tabMedia.get(tabId)
  if (!tab.has(frameId)) tab.set(frameId, new Map())
  return tab.get(frameId)
}

function addMediaEntry(tabId, frameId, url, entry) {
  const bucket = getFrameBucket(tabId, frameId)
  if (bucket.has(url)) return
  bucket.set(url, entry)
  // Evict oldest entries if over cap
  if (bucket.size > FRAME_BUCKET_MAX) {
    const sorted = Array.from(bucket.entries()).sort((a, b) => a[1].timestamp - b[1].timestamp)
    const toRemove = sorted.slice(0, bucket.size - FRAME_BUCKET_MAX)
    for (const [k] of toRemove) bucket.delete(k)
  }
  scheduleTabMediaSave()
}

function getFrameMedia(tabId, frameId) {
  const tab = tabMedia.get(tabId)
  if (!tab) return []
  const bucket = tab.get(frameId)
  return bucket ? Array.from(bucket.values()) : []
}

function getAllTabMedia(tabId) {
  const tab = tabMedia.get(tabId)
  if (!tab) return []
  const seen = new Set()
  const result = []
  for (const bucket of tab.values()) {
    for (const [url, entry] of bucket) {
      if (!seen.has(url)) {
        seen.add(url)
        result.push(entry)
      }
    }
  }
  return result
}

// --- Action / tab event handlers ---

/** Launch the Mac app when localhost is down, then keep polling for /ping. */
function injectPageWakeGesture(_tabId, _request) {
  return launchMacAppForDownload()
}

chrome.action.onClicked.addListener(async (tab) => {
  if (!tab.url) return
  const now = Date.now()
  if (now - lastClickTime < DEBOUNCE_MS) return
  lastClickTime = now

  if (isYouTubeUrl(tab.url)) {
    let downloadUrl = tab.url

    if (!/[?&]v=/.test(tab.url)) {
      try {
        const [result] = await chrome.scripting.executeScript({
          target: { tabId: tab.id },
          func: () => {
            const player = document.querySelector('#movie_player')
            return player?.getVideoUrl?.() || null
          }
        })
        if (result?.result) downloadUrl = result.result
      } catch {}
    }

    if (/[?&]v=/.test(downloadUrl)) {
      await injectPageWakeGesture(tab.id, { url: downloadUrl })
      await sendDownloadRequest({ url: downloadUrl }, tab.id, { surfacedWake: true })
    }
  }

  if (isDouyinUrl(tab.url)) {
    try {
      await syncCookies({ forced: true })
      await chrome.scripting.executeScript({
        target: { tabId: tab.id },
        func: () => {
          const btn = document.getElementById('dy-dl-btn')
          if (btn) btn.click()
        }
      })
    } catch {}
  }

  if (isXUrl(tab.url)) {
    const statusUrl = getXStatusUrl(tab.url)
    if (statusUrl) {
      await injectPageWakeGesture(tab.id, { url: statusUrl })
      await sendDownloadRequest({ url: statusUrl }, tab.id, { surfacedWake: true })
    }
  }
})

chrome.tabs.onActivated.addListener(async (activeInfo) => {
  try {
    const tab = await chrome.tabs.get(activeInfo.tabId)
    updateTabUI(tab)
  } catch {}
})

chrome.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  if (changeInfo.url || changeInfo.status === 'complete') {
    updateTabUI(tab)
  }
  if (changeInfo.url) {
    tabMedia.delete(tabId)
    scheduleTabMediaSave()
    updateBadge(tabId, 0)
  }
})

chrome.tabs.onRemoved.addListener((tabId) => {
  tabMedia.delete(tabId)
  scheduleTabMediaSave()
})

function updateTabUI(tab) {
  if (!tab.active || !tab.id) return
  const isYT = tab.url && isYouTubeUrl(tab.url)
  const isDouyin = tab.url && isDouyinUrl(tab.url)
  const isX = tab.url && isXUrl(tab.url)

  const noPopup = isYT || isDouyin || isX
  chrome.action.setPopup({ tabId: tab.id, popup: noPopup ? '' : 'popup.html' })
  chrome.action.setIcon({ tabId: tab.id, path: ICON_ACTIVE })

  if (!isYT) {
    const count = (isDouyin || isX) ? 0 : getAllTabMedia(tab.id).length
    updateBadge(tab.id, count)
  }
}

function updateBadge(tabId, count) {
  if (count > 0) {
    chrome.action.setBadgeText({ tabId, text: String(count) })
    chrome.action.setBadgeBackgroundColor({ tabId, color: '#27272A' })
    chrome.action.setIcon({ tabId, path: ICON_ACTIVE })
  } else {
    chrome.action.setBadgeText({ tabId, text: '' })
  }
}

// --- webRequest sniffer (frame-aware) ---

chrome.webRequest.onCompleted.addListener(
  (details) => {
    if (details.tabId < 0) return
    if (isYouTubeUrl(details.url)) return
    if (isDouyinUrl(details.initiator || '') || isDouyinUrl(details.url)) return
    if (isXUrl(details.initiator || '') || /video\.twimg\.com/.test(details.url)) return
    if (details.statusCode < 200 || details.statusCode >= 400) return

    let mediaType = null
    for (const { pattern, type } of MEDIA_PATTERNS) {
      if (pattern.test(details.url)) {
        mediaType = type
        break
      }
    }

    if (!mediaType) {
      const contentType = getHeader(details.responseHeaders, 'content-type')
      if (contentType) {
        if (contentType.includes('mpegurl') || contentType.includes('x-mpegurl')) {
          mediaType = 'hls'
        } else if (contentType.includes('video/mp4')) {
          mediaType = 'mp4'
        } else if (contentType.includes('video/webm')) {
          mediaType = 'webm'
        } else if (contentType.includes('video/x-flv')) {
          mediaType = 'flv'
        }
      }
    }
    if (!mediaType) return

    if (!SIZE_EXEMPT_TYPES.has(mediaType)) {
      const contentLength = getHeader(details.responseHeaders, 'content-length')
      if (contentLength && parseInt(contentLength) < MIN_VIDEO_SIZE) return
    }

    const contentLength = getHeader(details.responseHeaders, 'content-length')
    const frameId = details.frameId ?? 0
    addMediaEntry(details.tabId, frameId, details.url, {
      url: details.url,
      type: mediaType,
      size: contentLength ? parseInt(contentLength) : null,
      initiator: details.initiator || '',
      timestamp: Date.now()
    })

    updateBadge(details.tabId, getAllTabMedia(details.tabId).length)
  },
  { urls: ['<all_urls>'], types: ['media', 'xmlhttprequest', 'other'] },
  ['responseHeaders']
)

function getHeader(headers, name) {
  if (!headers) return null
  const header = headers.find((h) => h.name.toLowerCase() === name.toLowerCase())
  return header ? header.value : null
}

// --- Message handlers ---

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (sender.id !== chrome.runtime.id) return
  if (message.type === 'CLEAR_LAST_DOWNLOAD_ERROR') {
    clearLastDownloadError()
    sendResponse({ ok: true })
    return false
  }

  if (message.type === 'FORCE_COOKIE_SYNC') {
    ;(async () => {
      registeredThisSession = false
      const result = await syncCookies({ forced: true })
      sendResponse({
        ok: result.ok,
        error: result.ok
          ? undefined
          : (result.error || 'App did not accept cookies (is Mac All You Need running on this machine?)')
      })
      const tabId = sender.tab?.id
      const url = sender.tab?.url ?? ''
      if (
        result.ok &&
        tabId !== undefined &&
        url.startsWith(`${APP_URL}/cookie-sync-landing`)
      ) {
        setTimeout(() => {
          chrome.tabs.remove(tabId, () => void chrome.runtime.lastError)
        }, 450)
      }
    })()
    return true
  }

  // Existing: YouTube content.js download button
  if (message.type === 'DOWNLOAD_VIDEO') {
    const surfacedWake = message.surfacedWake === true
    sendDownloadRequest({ url: message.url }, sender.tab?.id, { surfacedWake })
      .then((ok) => sendResponse(ok ? { ok: true } : { error: true }))
      .catch(() => sendResponse({ error: true }))
    return true
  }

  // Existing: popup queries all media for the active tab
  if (message.type === 'GET_MEDIA') {
    chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
      const tabId = tabs[0]?.id
      if (!tabId) {
        sendResponse({ media: [], tabUrl: '', tabTitle: '' })
        return
      }
      const media = getAllTabMedia(tabId)
      sendResponse({ media, tabUrl: tabs[0].url || '', tabTitle: tabs[0].title || '' })
    })
    return true
  }

  // Existing: popup triggers multi-item download
  if (message.type === 'DOWNLOAD_MEDIA') {
    const { items, tabUrl, tabTitle } = message
    const surfacedWake = message.surfacedWake === true
    const baseTitle = tabTitle || 'download'
    chrome.tabs.query({ active: true, currentWindow: true }, async (tabs) => {
      const tabId = tabs[0]?.id || null
      const requests = items.map((item, i) => ({
        url: item.url,
        type: item.type,
        referer: item.initiator || tabUrl || '',
        title: items.length > 1 ? `${baseTitle} (${i + 1})` : baseTitle
      }))

      try {
        await syncCookies({ forced: true })
        const firstRes = await authedFetch('/download', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(requests[0])
        })
        if (firstRes.ok) {
          clearLastDownloadError()
          for (let i = 1; i < requests.length; i++) {
            await authedFetch('/download', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify(requests[i])
            })
          }
          sendResponse({ ok: true })
          return
        }
      } catch {
        // App not running — postDownloadsQueueWhenReady launches via mayn:// and polls.
      }
      const posted = await postDownloadsQueueWhenReady(requests)
      if (!posted) {
        setLastDownloadError(
          'Could not queue download: app unreachable. Check that Mac All You Need is running.'
        )
      }
      sendResponse({ ok: posted })
    })
    return true
  }

  // New: content overlay queries media for its specific frame, with tab-level fallback
  if (message.type === 'GET_FRAME_MEDIA') {
    const tabId = sender.tab?.id
    const frameId = sender.frameId ?? 0
    if (!tabId) {
      sendResponse({ media: [], source: 'none', frameId })
      return true
    }
    const frameMedia = getFrameMedia(tabId, frameId)
    const tabMedia = getAllTabMedia(tabId)

    const mergedByKey = new Map()
    for (const m of frameMedia) {
      const key = `${m.url}|${m.type}`
      mergedByKey.set(key, m)
    }
    for (const m of tabMedia) {
      const key = `${m.url}|${m.type}`
      const prev = mergedByKey.get(key)
      if (!prev || (m.timestamp || 0) > (prev.timestamp || 0)) {
        mergedByKey.set(key, m)
      }
    }
    const media = Array.from(mergedByKey.values()).sort((a, b) => (b.timestamp || 0) - (a.timestamp || 0))

    let source = 'frame'
    if (frameMedia.length > 0 && tabMedia.length > 0) source = 'frame+tab'
    else if (frameMedia.length === 0 && tabMedia.length > 0) source = 'tab-fallback'
    else if (frameMedia.length === 0) source = 'none'

    sendResponse({
      media,
      source,
      frameId,
      isYouTube: isYouTubeUrl(sender.tab.url || ''),
      pageTitle: sender.tab.title || ''
    })
    return true
  }

  // Content scripts → localhost: use return true + sendResponse (Promise return is flaky in some Chrome MV3 builds).
  if (message.type === 'DOWNLOAD_MEDIA_FROM_CONTENT') {
    const { item } = message
    const surfacedWake = message.surfacedWake === true
    const tabId = sender.tab?.id
    const tabUrl = sender.tab?.url || ''
    const tabTitle = sender.tab?.title || 'download'

    if (!item || !item.url) {
      logBg('download-from-content-bad-item', { tabId, hasItem: !!item })
      sendResponse({ ok: false, error: 'Missing item or url' })
      return false
    }

    const request = {
      url: item.url,
      type: item.type,
      referer: item.initiator || tabUrl,
      title: (item.title && String(item.title).trim()) || tabTitle,
      awemeId: item.awemeId ? String(item.awemeId) : undefined,
      pageURL: item.pageURL ? String(item.pageURL) : undefined
    }

    logBg('download-from-content-start', {
      tabId,
      type: item.type,
      url: truncateUrl(item.url),
      referer: truncateUrl(request.referer, 48),
      title: (request.title || '').slice(0, 80)
    })

    let responded = false
    const safeSend = (payload) => {
      if (responded) return
      responded = true
      try {
        sendResponse(payload)
      } catch (e) {
        logBg('download-from-content-sendResponse-failed', { err: String(e) })
      }
    }

    ;(async () => {
      try {
        const cookiesOk = await syncCookies({ forced: true })
        logBg('download-from-content-sync-cookies', { cookiesOk })
        const res = await authedFetch('/download', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(request)
        })
        logBg('download-from-content-fetch', { status: res.status, ok: res.ok })
        if (res.ok) {
          clearLastDownloadError()
          safeSend({ ok: true })
          return
        }
      } catch (e) {
        logBg('download-from-content-fetch-catch', { err: String(e) })
      }
      try {
        logBg('download-from-content-cold-wake', { tabId, surfacedWake })
        await launchMacAppForDownload()
        const ok = await postDownloadWhenAppReady(request)
        logBg('download-from-content-after-wake', { ok })
        if (ok) clearLastDownloadError()
        else {
          setLastDownloadError(
            'Could not send this stream to Mac All You Need. Confirm the app is running and try again.'
          )
        }
        safeSend({ ok })
      } catch (err) {
        logBg('download-from-content-wake-catch', { err: String(err) })
        safeSend({ ok: false, error: String(err) })
      }
    })()
    return true
  }

  return false
})

function isYouTubeUrl(url) {
  return /^https?:\/\/(www\.)?(youtube\.com|youtu\.be|music\.youtube\.com)/.test(url)
}

function isDouyinUrl(url) {
  return /^https?:\/\/([a-z0-9-]+\.)?(douyin|iesdouyin)\.com/i.test(url)
}

function isXUrl(url) {
  return /^https?:\/\/(www\.)?(x\.com|twitter\.com)/.test(url)
}

function getXStatusUrl(url) {
  const m = url.match(/https:\/\/(x|twitter)\.com\/[^/]+\/status\/\d+/)
  return m ? m[0] : null
}

async function sendDownloadRequest(request, tabId, opts = {}) {
  const payload = typeof request === 'object' && request !== null ? request : { url: String(request) }
  try {
    await syncCookies({ forced: true })
    const res = await authedFetch('/download', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    })
    if (res.ok) {
      clearLastDownloadError()
      return true
    }
  } catch {
    /* app not running */
  }
  await injectPageWakeGesture(tabId, payload)
  let ok = await postDownloadWhenAppReady(payload)
  if (!ok) {
    setLastDownloadError('Could not reach Mac All You Need from the extension.')
  } else {
    clearLastDownloadError()
  }
  return ok
}

async function syncCookies(opts = {}) {
  const now = Date.now()
  if (!opts.forced && now - lastCookieSyncAt < 60000) {
    return { ok: false, error: 'Cookie sync was skipped (synced recently).' }
  }
  lastCookieSyncAt = now
  const registration = await ensureRegistered({ force: opts.forced === true })
  if (!registration.ok) {
    return { ok: false, error: registration.error }
  }
  try {
    const allCookies = []
    for (const domain of COOKIE_SYNC_DOMAINS) {
      const cookies = await chrome.cookies.getAll({ domain })
      allCookies.push(...cookies.map((c) => ({
        name: c.name,
        value: c.value,
        domain: c.domain,
        path: c.path,
        secure: c.secure,
        httpOnly: c.httpOnly,
        expirationDate: c.expirationDate
      })))
    }

    const body = JSON.stringify(allCookies)
    const appRes = await authedFetch('/cookies', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body
    })
    if (appRes.ok) return { ok: true }
    const serverError = await readServerError(appRes)
    return {
      ok: false,
      error: serverError || appRes._error || 'App did not accept cookies (is Mac All You Need running on this machine?)'
    }
  } catch {
    return {
      ok: false,
      error: 'Could not reach Mac All You Need on localhost:18765 (is the app running?)'
    }
  }
}

async function pollPendingCookieSync() {
  try {
    const poll = await authedFetch('/cookie-sync-poll')
    if (!poll.ok) return
    const data = await poll.json()
    if (!data.pending) return
    await syncCookies()
  } catch {
    // app not running
  }
}

chrome.runtime.onInstalled.addListener(async () => {
  const r = await chrome.storage.local.get('maynAuthToken')
  if (!r.maynAuthToken) await chrome.storage.local.set({ maynAuthToken: crypto.randomUUID() })
  syncCookies()
  cleanupLastDownloadError()
  chrome.contextMenus.create({
    id: 'sync-cookies-now',
    title: 'Sync cookies to Mac All You Need',
    contexts: ['action'],
  })
})

chrome.contextMenus.onClicked.addListener((info) => {
  if (info.menuItemId === 'sync-cookies-now') {
    syncCookies()
  }
})

chrome.runtime.onStartup.addListener(() => {
  syncCookies()
  cleanupLastDownloadError()
})

chrome.alarms.create('sync-cookies', { periodInMinutes: 5 })
chrome.alarms.create('cookie-sync-force-poll', { periodInMinutes: 1 })
chrome.alarms.create('last-download-error-gc', { periodInMinutes: 5 })
chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === 'sync-cookies') {
    syncCookies({ forced: true })
  } else if (alarm.name === 'cookie-sync-force-poll') {
    void pollPendingCookieSync()
  } else if (alarm.name === 'last-download-error-gc') {
    cleanupLastDownloadError()
  }
})
