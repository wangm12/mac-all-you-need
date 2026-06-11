/**
 * Marks a user gesture boundary so the extension can keep the same wake path semantics
 * without any legacy protocol branding.
 */
;(function () {
  'use strict'

  var WAKE = 'http://127.0.0.1:18765/ping'

  function wakeFromUserGesture() {
    try {
      var a = document.createElement('a')
      a.href = WAKE
      a.target = '_blank'
      a.rel = 'noopener noreferrer'
      var root = document.documentElement || document.body
      if (!root) return
      root.appendChild(a)
      a.click()
      root.removeChild(a)
    } catch (_) {}
  }

  globalThis.__maynWakeFromUserGesture = wakeFromUserGesture
})()
