import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "TrayState.js" as TrayState

Panel {
  id: root
  moduleName: "aerorohit.nextcloud"
  ipcTarget: "aerorohit.nextcloud"
  manageIpc: false

  property string userConfigPath: Quickshell.env("HOME") + "/.config/omarchy"
  property string focusSection: "app"
  property int fileIndex: 0
  property bool cursorActive: false
  property int phraseIndex: 0

  readonly property var activePhrases: [
    "Syncing files",
    "Clouding data",
    "Sharing storage",
    "Connecting dots",
    "Mirroring files",
    "Backing up bytes",
    "Syncing secrets",
    "Moving memories",
    "Wrangling revisions",
    "Cataloging cloud"
  ]
  readonly property string heroPhraseText: activePhrases[phraseIndex % activePhrases.length]
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color iconColor: nextcloud.authenticated && nextcloud.syncEnabled ? foreground : dim
  readonly property string toggleHint: nextcloud.syncEnabled ? "Pause syncing" : "Resume syncing"
  readonly property color barIconColor: nextcloud.authenticated && nextcloud.syncEnabled ? barForeground : Qt.darker(barForeground, 1.55)

  readonly property bool headerHasCursor: cursorActive && focusSection === "header" && nextcloud.installed

  readonly property string appRowTitle: !nextcloud.installed ? "Nextcloud desktop is not installed"
    : (nextcloud.authenticated ? "Open Nextcloud app" : "Open Nextcloud")
  readonly property string appRowMeta: !nextcloud.installed ? "Install the desktop sync client"
    : (nextcloud.authenticated ? "Settings, activity and folders" : "Sign in and choose what to sync")

  function ensureCursor() {
    if (!nextcloud.authenticated) {
      focusSection = "app"
      fileIndex = 0
      return
    }
    if (focusSection === "app") return
    if (nextcloud.files.length === 0) {
      focusSection = "header"
      fileIndex = 0
      return
    }
    if (focusSection !== "files" && focusSection !== "header") focusSection = "files"
    if (fileIndex >= nextcloud.files.length) fileIndex = Math.max(0, nextcloud.files.length - 1)
    if (fileIndex < 0) fileIndex = 0
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    ensureCursor()
    if (dy === 0) return
    if (focusSection === "app") {
      if (dy < 0 && nextcloud.authenticated) {
        if (nextcloud.files.length > 0) {
          focusSection = "files"
          fileIndex = nextcloud.files.length - 1
        } else {
          setHeaderCursor()
        }
        scrollCursorIntoView()
      }
      return
    }
    if (focusSection === "header") {
      if (dy > 0) {
        if (nextcloud.files.length > 0) {
          focusSection = "files"
          fileIndex = 0
        } else {
          focusSection = "app"
        }
        scrollCursorIntoView()
      }
      return
    }
    if (focusSection === "files") {
      if (dy < 0 && fileIndex === 0) {
        setHeaderCursor()
        return
      }
      if (dy > 0 && fileIndex === nextcloud.files.length - 1) {
        focusSection = "app"
        scrollCursorIntoView()
        return
      }
      fileIndex = Math.max(0, Math.min(nextcloud.files.length - 1, fileIndex + dy))
      scrollCursorIntoView()
    }
  }

  function setHeaderCursor() {
    cursorActive = true
    focusSection = "header"
    if (panelFlick) panelFlick.contentY = 0
  }

  function toggleRunning() {
    if (nextcloud.installed && !nextcloud.busy) nextcloud.toggleSync()
  }

  function activateCursor() {
    ensureCursor()
    if (focusSection === "app") activateAppRow()
    else if (focusSection === "header") toggleRunning()
    else if (focusSection === "files") nextcloud.openFile(selectedFile())
  }

  function activateAppRow() {
    if (!nextcloud.installed) nextcloud.installDesktop()
    else nextcloud.openApp()
  }

  function setAppCursor() {
    cursorActive = true
    focusSection = "app"
    scrollCursorIntoView()
  }

  function selectedFile() {
    if (nextcloud.files.length === 0) return null
    return nextcloud.files[Math.max(0, Math.min(fileIndex, nextcloud.files.length - 1))]
  }

  function setFileCursor(index) {
    cursorActive = true
    focusSection = "files"
    fileIndex = index
    scrollCursorIntoView()
  }

  function scrollItemIntoView(item) {
    if (!panelFlick || !item) return
    Qt.callLater(function() {
      if (!item) return
      var margin = Style.space(6)
      var point = item.mapToItem(panelFlick.contentItem, 0, 0)
      var top = point.y
      var bottom = top + item.height
      var viewTop = panelFlick.contentY
      var viewBottom = viewTop + panelFlick.height
      var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (top < viewTop + margin) panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom > viewBottom - margin) panelFlick.contentY = Math.min(maxY, bottom + margin - panelFlick.height)
    })
  }

  function scrollCursorIntoView() {
    if (focusSection === "app" && appRow) {
      scrollItemIntoView(appRow)
      return
    }
    if (focusSection === "files" && fileColumn && fileIndex >= 0 && fileIndex < fileColumn.children.length) {
      scrollItemIntoView(fileColumn.children[fileIndex])
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    if (panelFlick) panelFlick.contentY = 0
    nextcloud.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  onFileIndexChanged: scrollCursorIntoView()

  // While this widget sits on the bar, the desktop client's own tray icon is
  // redundant — park it in the tray's hidden list. The icon is put back once
  // the plugin leaves the bar (disable, remove, or bar switch).
  readonly property string trayWidgetId: "omarchy.tray"
  readonly property string trayItemId: "Nextcloud"

  function findTrayEntry(cfg) {
    if (!cfg || !cfg.bar || !cfg.bar.layout) return null
    var sections = ["left", "center", "right"]
    for (var s = 0; s < sections.length; s++) {
      var entries = cfg.bar.layout[sections[s]]
      if (!Array.isArray(entries)) continue
      for (var i = 0; i < entries.length; i++) {
        var entry = entries[i]
        if (entry && String(entry.id || "") === trayWidgetId) return entry
      }
    }
    return null
  }

  function hideTrayItem() {
    if (!bar || !bar.shell || typeof bar.shell.mutateShellConfig !== "function") return
    var itemId = trayItemId
    try {
      var entry = findTrayEntry(bar.shell.shellConfig)
      var current = entry && Array.isArray(entry.hidden) ? entry.hidden : []
      if (current.indexOf(itemId) !== -1) return
      bar.shell.mutateShellConfig(function(cfg) {
        var target = root.findTrayEntry(cfg)
        if (!target) return
        var list = Array.isArray(target.hidden) ? target.hidden.slice() : []
        if (list.indexOf(itemId) === -1) list.push(itemId)
        target.hidden = list
      })
    } catch (error) {
      console.warn("nextcloud: could not hide tray icon:", error)
    }
  }

  // Widget destruction also fires on shell restarts and bar layout rebuilds,
  // where the plugin stays enabled and the icon should remain hidden — so the
  // restore runs detached, after a grace period, and only when the plugin is
  // genuinely gone from the bar. It edits shell.json directly (the qs IPC
  // cannot pass arrays), which also covers the shell not running at all.
  function scheduleTrayItemRestore() {
    var check = "omarchy-shell shell listPlugins 2>/dev/null"
      + " | jq -e '.[] | select(.id == \"aerorohit.nextcloud\" and .enabled == true)' >/dev/null 2>&1"
    var unhide = "cfg=\"$HOME/.config/omarchy/shell.json\"; tmp=$(mktemp)"
      + " && jq '.bar.layout |= with_entries(.value |= map("
      + "if (type == \"object\" and .id == \"omarchy.tray\") "
      + "then .hidden = [.hidden | if type == \"array\" then .[] else empty end | select(. != \"Nextcloud\")] "
      + "else . end))' \"$cfg\" > \"$tmp\" && mv \"$tmp\" \"$cfg\""
    Quickshell.execDetached(["bash", "-c",
      "sleep 2; if " + check + "; then exit 0; fi; " + unhide])
  }

  Component.onCompleted: {
    TrayState.acquire()
    hideTrayItem()
  }
  Component.onDestruction: if (TrayState.release()) scheduleTrayItemRestore()
  onBarChanged: if (bar) hideTrayItem()

  Service {
    id: nextcloud
    settings: root.settings
    userConfigPath: root.userConfigPath
  }

  Connections {
    target: nextcloud
    function onAuthenticatedChanged() { root.ensureCursor() }
    function onFilesChanged() { root.ensureCursor() }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { nextcloud.refresh(); return "ok" }
    function install(): string { nextcloud.installDesktop(); return "ok" }
    function openApp(): string { nextcloud.openApp(); return "ok" }
    function status(): string { return nextcloud.statusText }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        NextcloudIcon {
          anchors.centerIn: parent
          iconSize: Style.space(12)
          color: root.barIconColor
          opacity: nextcloud.syncEnabled ? 1.0 : 0.6
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) nextcloud.refresh()
      else if (buttonCode === Qt.MiddleButton) nextcloud.openApp()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") nextcloud.refresh()
        else if ((t === "o" || t === "O") && nextcloud.installed) nextcloud.openApp()
        else if ((t === "i" || t === "I") && !nextcloud.installed) nextcloud.installDesktop()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          Item {
            id: header
            visible: nextcloud.authenticated
            width: parent.width
            implicitHeight: hero.implicitHeight
            readonly property bool ringVisible: root.headerHasCursor
            function focusHero() { root.setHeaderCursor() }

            PanelHero {
              id: hero
              width: parent.width
              title: "Nextcloud"
              meta: nextcloud.syncEnabled ? root.heroPhraseText : "Syncing paused"
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: nextcloud.syncEnabled ? 1.0 : 0.5
              iconComponent: Component {
                NextcloudIcon {
                  iconSize: Style.font.display
                  color: root.iconColor
                }
              }

              trailingControl: Component {
                ToggleSwitch {
                  id: powerSwitch
                  visible: nextcloud.installed
                  checked: nextcloud.syncEnabled
                  busy: nextcloud.busy
                  hasCursor: header.ringVisible
                  foreground: hero.foreground
                  onHovered: function(on) { if (on) header.focusHero() }
                  onToggled: root.toggleRunning()

                  PanelToolTip {
                    visible: powerSwitch.containsMouse
                    text: root.toggleHint
                    fontFamily: hero.fontFamily
                  }
                }
              }
            }
          }

          Text {
            visible: nextcloud.actionStatus !== "" || nextcloud.lastError !== ""
            width: parent.width
            text: nextcloud.actionStatus !== "" ? nextcloud.actionStatus : nextcloud.lastError
            textFormat: Text.PlainText
            color: nextcloud.lastError !== "" && nextcloud.actionStatus === "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Column {
            visible: nextcloud.authenticated
            width: parent.width
            spacing: Style.spacing.labelGap

            Column {
              width: parent.width
              spacing: Style.spacing.labelGap
              InfoPair { label: "Stored"; value: Model.usageText(nextcloud.usedBytes, nextcloud.quotaBytes, nextcloud.quotaKnown) }
              InfoPair { label: "Server"; value: nextcloud.serverUrl !== "" ? nextcloud.serverUrl : "Not configured" }
            }
          }

          PanelSeparator {
            visible: appRow.visible
            foreground: root.foreground
          }

          AppRow {
            id: appRow
            visible: nextcloud.probed
            width: parent.width
          }

          PanelSeparator {
            visible: nextcloud.authenticated
            foreground: root.foreground
          }

          Column {
            visible: nextcloud.authenticated
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "RECENT FILES"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              visible: nextcloud.files.length === 0
              width: parent.width
              text: "No synced files found."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
            }

            Column {
              id: fileColumn
              visible: nextcloud.files.length > 0
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: nextcloud.files
                FileRow {
                  required property var modelData
                  required property int index
                  width: fileColumn.width
                  file: modelData
                  rowIndex: index
                }
              }
            }
          }
        }
      }
    }
  }

  Timer {
    id: phraseTimer
    interval: 2800
    running: root.opened && nextcloud.authenticated && nextcloud.syncEnabled
    repeat: true
    onTriggered: phraseSwap.restart()
  }

  SequentialAnimation {
    id: phraseSwap
    PropertyAnimation {
      target: hero; property: "metaOpacity"
      to: 0.0; duration: 180; easing.type: Easing.OutQuad
    }
    ScriptAction {
      script: root.phraseIndex = (root.phraseIndex + 1) % root.activePhrases.length
    }
    PropertyAnimation {
      target: hero; property: "metaOpacity"
      to: 1.0; duration: 260; easing.type: Easing.InQuad
    }
  }

  // Bottom action row: an install prompt while the desktop client is missing,
  // and an "open the app" shortcut once it is installed.
  component AppRow: CursorSurface {
    id: appRowItem

    hasCursor: root.cursorActive && root.focusSection === "app"
    foreground: root.foreground

    implicitHeight: appRowContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setAppCursor()
      onClicked: root.activateAppRow()
    }

    RowLayout {
      id: appRowContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        text: nextcloud.installed ? "" : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: root.appRowTitle
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: root.appRowMeta
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      PanelActionButton {
        iconText: nextcloud.installed ? "󰌼" : "󰇚"
        foreground: root.foreground
        fontFamily: root.fontFamily
        Layout.alignment: Qt.AlignVCenter
        onClicked: root.activateAppRow()
      }
    }
  }

  component FileRow: CursorSurface {
    id: fileRow
    property var file: null
    property int rowIndex: 0
    readonly property string fileName: file ? String(file.name || "Untitled") : "Untitled"

    hasCursor: root.cursorActive && root.focusSection === "files" && root.fileIndex === rowIndex
    foreground: root.foreground

    implicitHeight: fileContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setFileCursor(fileRow.rowIndex)
      onClicked: nextcloud.openFile(fileRow.file)
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        text: Model.fileGlyph(fileRow.fileName)
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        id: fileContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: fileRow.fileName
          textFormat: Text.PlainText
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: Model.fileMeta(fileRow.file)
          textFormat: Text.PlainText
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""

    width: parent.width
    spacing: Style.space(8)

    InfoLabel { text: label }
    Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2); height: 1 }
    InfoValue { text: value }
  }

  component InfoLabel: Text {
    color: root.foreground
    opacity: 0.6
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component InfoValue: Text {
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    elide: Text.ElideRight
    // Synced data (server URL, folder names) is untrusted: never let AutoText
    // interpret it as markup, which could load remote images when shown.
    textFormat: Text.PlainText
  }
}
