import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})
  property string userConfigPath: Quickshell.env("HOME") + "/.config/omarchy"

  property bool installed: false
  property bool running: false
  property bool authenticated: false
  // False until the first successful status probe, so the panel does not flash
  // the install prompt while the initial check is still in flight.
  property bool probed: false

  property bool refreshing: false
  property string statusText: "Checking…"
  property string accountPath: ""
  property string serverUrl: ""
  property double usedBytes: 0
  property double quotaBytes: 0
  property double usagePercent: 0
  property bool quotaKnown: false
  property var files: []
  property string actionStatus: ""
  property string lastError: ""
  property string dbusStatus: "unknown"

  // Optimistic sync state — like Dropbox's _desired. -1 means follow the real
  // D-Bus state; 0/1 means a toggle is in flight and the UI should show the
  // target state until the real state catches up.
  property int _desired: -1
  readonly property bool syncEnabled: _desired === -1 ? (dbusStatus !== "paused" && dbusStatus !== "unknown") : (_desired === 1)

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 60, 10, 3600)
  readonly property bool busy: statusProcess.running
  readonly property string helperPath: (userConfigPath || "") + "/plugins/aerorohit.nextcloud/status.py"
  readonly property string installScriptPath: (userConfigPath || "") + "/plugins/aerorohit.nextcloud/omarchy-install-service-nextcloud"
  readonly property int MAX_STATUS_OUTPUT_BYTES: 256 * 1024
  readonly property int MAX_TOGGLE_OUTPUT_BYTES: 32 * 1024

  property string _statusOutput: ""
  property string _statusError: ""
  property string _toggleStdout: ""
  property string _toggleStderr: ""

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    if (n < min) n = min
    if (n > max) n = max
    return n
  }

  function refresh() {
    if (statusProcess.running || helperPath === "") return
    _statusOutput = ""
    _statusError = ""
    refreshing = true
    statusProcess.command = ["python3", helperPath, "25"]
    statusProcess.running = true
  }

  function applyStatus(raw) {
    var parsed = Model.parseStatus(raw)
    if (!parsed.ok) {
      lastError = parsed.lastError || "Failed to read Nextcloud status"
      return
    }
    installed = parsed.installed === true
    running = parsed.running === true
    authenticated = parsed.authenticated === true
    var st = String(parsed.statusText || (installed ? "Stopped" : "Not installed"))
    statusText = st.length > 500 ? st.substring(0, 497) + "…" : st
    var ap = String(parsed.accountPath || "")
    accountPath = ap.length > 1000 ? ap.substring(0, 997) + "…" : ap
    var su = String(parsed.serverUrl || "")
    serverUrl = su.length > 500 ? su.substring(0, 497) + "…" : su
    usedBytes = Number(parsed.usedBytes || 0)
    quotaBytes = Number(parsed.quotaBytes || 0)
    usagePercent = Number(parsed.usagePercent || 0)
    quotaKnown = parsed.quotaKnown === true
    var src = parsed.files || []
    var maxFiles = 100
    files = []
    for (var i = 0; i < src.length && i < maxFiles; i++) {
      var f = src[i]
      if (f && typeof f === "object" && f.name && f.path) files.push(f)
    }
    dbusStatus = String(parsed.dbusStatus || "unknown")
    if (_desired !== -1 && syncEnabled === (_desired === 1)) _desired = -1
    lastError = ""
  }

  function elideStatus(text) {
    var value = String(text || "").replace(/\s+/g, " ").trim()
    return value.length > 140 ? value.substring(0, 137) + "…" : value
  }

  function openFile(file) {
    if (!file || !file.path) return
    var p = String(file.path).trim()
    if (p === "" || p.indexOf("..") !== -1 || p.indexOf("\n") !== -1) return
    Quickshell.execDetached(["xdg-open", p])
  }

  function openApp() {
    if (installed) {
      Quickshell.execDetached(["nextcloud"])
    }
  }

  // pacman needs a tty for the sudo password, so the install runs in a
  // terminal window rather than detached like the other actions.
  function installDesktop() {
    if (installed || installWatch.running) return
    actionStatus = "Opening installer…"
    actionStatusTimer.restart()
    installWatch.ticks = 0
    installWatch.restart()
    Quickshell.execDetached(["omarchy-launch-terminal", "bash", "-c",
      "bash \"" + installScriptPath + "\"; echo; read -n 1 -s -r -p 'Press any key to close…'"])
  }

  function toggleSync() {
    if (!installed || toggleProcess.running) return
    _desired = syncEnabled ? 0 : 1
    actionStatus = _desired === 0 ? "Pausing sync…" : "Resuming sync…"
    toggleProcess.command = ["python3", helperPath, "--toggle"]
    toggleProcess.running = true
  }

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: startupRamp
    property int ticks: 0
    interval: 2000
    repeat: true
    running: true
    onTriggered: {
      ticks += 1
      if (root.dbusStatus !== "unknown" || ticks >= 15) startupRamp.running = false
      else root.refresh()
    }
  }

  Timer {
    id: settleTimer
    property int ticks: 0
    interval: 1500
    repeat: true
    running: false
    onTriggered: {
      settleTimer.ticks += 1
      root.refresh()
      if (settleTimer.ticks >= 4) {
        settleTimer.ticks = 0
        settleTimer.running = false
        root._desired = -1
      }
    }
  }

  Timer {
    id: delayedRefresh
    interval: 1000
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    // Poll quickly after kicking off the installer so the panel flips to the
    // installed state soon after pacman finishes, instead of waiting for the
    // next periodic refresh.
    id: installWatch
    property int ticks: 0
    interval: 3000
    repeat: true
    running: false
    onTriggered: {
      ticks += 1
      if (root.installed || ticks >= 100) running = false
      else root.refresh()
    }
  }

  Timer {
    id: actionStatusTimer
    interval: 2200
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Process {
    id: statusProcess
    running: false
    command: []
    stdout: StdioCollector { id: statusStdout; waitForEnd: true; onStreamFinished: { var t = text; root._statusOutput = t.length > root.MAX_STATUS_OUTPUT_BYTES ? t.slice(0, root.MAX_STATUS_OUTPUT_BYTES) : t } }
    stderr: StdioCollector { id: statusStderr; waitForEnd: true; onStreamFinished: { var t = text; root._statusError = t.length > root.MAX_STATUS_OUTPUT_BYTES ? t.slice(0, root.MAX_STATUS_OUTPUT_BYTES) : t } }
    onExited: function(exitCode) {
      root.refreshing = false
      var stdout = String(statusStdout.text || root._statusOutput || "")
      var stderr = String(statusStderr.text || root._statusError || "")
      if (exitCode === 0) {
        root.probed = true
        root.applyStatus(stdout)
      } else {
        root.lastError = root.elideStatus(stderr || stdout || "Could not read Nextcloud status")
      }
    }
  }

  Process {
    id: toggleProcess
    running: false
    command: []
    stdout: StdioCollector { id: toggleStdout; waitForEnd: true; onStreamFinished: { var t = text; root._toggleStdout = t.length > root.MAX_TOGGLE_OUTPUT_BYTES ? t.slice(0, root.MAX_TOGGLE_OUTPUT_BYTES) : t } }
    stderr: StdioCollector { id: toggleStderr; waitForEnd: true; onStreamFinished: { var t = text; root._toggleStderr = t.length > root.MAX_TOGGLE_OUTPUT_BYTES ? t.slice(0, root.MAX_TOGGLE_OUTPUT_BYTES) : t } }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root._desired = -1
        root.lastError = "Failed to toggle sync"
        root.actionStatus = root.lastError
      } else {
        root.actionStatus = ""
      }
      actionStatusTimer.restart()
      settleTimer.ticks = 0
      settleTimer.restart()
    }
  }
}
