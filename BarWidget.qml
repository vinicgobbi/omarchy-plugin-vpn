import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "vinicgobbi.vpn"
  ipcTarget: "vinicgobbi.vpn"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  // Bar.qml fades barForeground toward the background whenever the bar
  // itself recedes (e.g. useTransparentForeground) — appropriate for the
  // small icon sitting in the bar, but not for this panel's own content,
  // which stays on the stable `foreground` above. Matches the native
  // tailscale panel's foreground/barIconColor split.
  readonly property color barForeground: bar ? bar.barForeground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color accent: Color.accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property int refreshIntervalSec: {
    var n = parseInt(String(setting("refreshIntervalSec", 10)), 10)
    return (isFinite(n)) ? Math.max(3, Math.min(300, n)) : 10
  }

  readonly property string vpnIcon: "󰖂"
  readonly property color iconColor: service.anyConnected ? barForeground : Qt.darker(barForeground, 1.55)
  readonly property string tooltipText: "Tailscale: " + service.tailscaleDetail +
    (service.tailscaleUp && service.tailscaleIp !== "" ? " (" + service.tailscaleIp + ")" : "") +
    (service.tailscaleUp ? "\n" + service.tailscaleOnlinePeerCount + "/" + service.tailscalePeerCount + " devices online" : "") +
    "\nOpenVPN: " +
    (service.ovProfiles.length === 0 ? "no profiles" :
     service.ovProfiles.filter(function(p) { return p.active }).length + "/" + service.ovProfiles.length + " connected")

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  onOpenedChanged: if (opened) service.refresh()

  // Resolve the bundled import-profile helper from this QML file so the
  // plugin works from any user's plugin directory and from git checkouts
  // with spaces in the path.
  function bundledPath(name) {
    return decodeURIComponent(String(Qt.resolvedUrl(name)).replace(/^file:\/\//, ""))
  }

  // The native file picker (`omarchy file select`) opening as its own
  // window causes this popup to auto-close (same as it would for a click
  // outside), so the import result — and the DNS/domain prompt below —
  // would otherwise be invisible until the user reopens the widget by
  // hand. Remember we were mid-import and pop the panel back open once the
  // helper process exits.
  property bool _reopenAfterImport: false

  function importOvProfile() {
    root._reopenAfterImport = true
    service.importOvProfile(root.bundledPath("import-profile"))
  }

  Connections {
    target: service
    function onOvImportBusyChanged() {
      if (!service.ovImportBusy && root._reopenAfterImport) {
        root._reopenAfterImport = false
        root.open()
      }
    }
  }

  // --- Rename/delete state for OpenVPN profiles ---
  property string renameUuid: ""
  property string renameOriginalName: ""
  property string renameName: ""
  property string pendingDeleteUuid: ""
  property string pendingDeleteName: ""

  // Whether to persist the credentials just entered on the NetworkManager
  // connection (so it won't ask again) or leave them as ask-every-time.
  // Reset to the default each time a new credential prompt opens.
  property bool credSaveCredentials: true

  function requestRename(profile) {
    cancelDelete()
    service.cancelCredentials()
    renameUuid = profile.uuid
    renameOriginalName = profile.name
    renameName = profile.name
  }

  function cancelRename() {
    renameUuid = ""
    renameOriginalName = ""
    renameName = ""
  }

  function confirmRename() {
    var nextName = renameName.replace(/[\r\n]/g, "").trim()
    if (renameUuid === "" || nextName === "" || nextName === renameOriginalName || service.ovBusyUuid !== "") return
    service.renameOvProfile(renameUuid, nextName)
    cancelRename()
  }

  function requestDelete(profile) {
    cancelRename()
    service.cancelCredentials()
    pendingDeleteUuid = profile.uuid
    pendingDeleteName = profile.name
  }

  function cancelDelete() {
    pendingDeleteUuid = ""
    pendingDeleteName = ""
  }

  function confirmDelete() {
    if (pendingDeleteUuid === "" || service.ovBusyUuid !== "") return
    service.deleteOvProfile(pendingDeleteUuid)
    cancelDelete()
  }

  VpnService {
    id: service
    refreshIntervalSec: root.refreshIntervalSec
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    slotSize: Style.bar.statusSlot
    tooltipText: root.tooltipText
    iconComponent: Component {
      Item {
        Text {
          anchors.centerIn: parent
          text: root.vpnIcon
          color: root.iconColor
          opacity: service.anyConnected ? 1 : 0.55
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
        }
      }
    }
    onPressed: function(code) { if (code === Qt.LeftButton) root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keys
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keys
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { if (t === "r" || t === "R") service.refresh() }

      Flickable {
        anchors.fill: parent
        contentWidth: width; contentHeight: content.implicitHeight
        clip: true; boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: content
          width: parent.width
          spacing: Style.space(14)

          Text {
            width: parent.width
            text: "VPN Manager"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }

          Text {
            visible: service.lastError !== ""
            width: parent.width
            text: service.lastError
            textFormat: Text.PlainText
            color: bar ? bar.urgent : Color.urgent
            wrapMode: Text.Wrap
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          // --- Tailscale section ---
          Column {
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: "TAILSCALE"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            CursorSurface {
              width: parent.width
              height: Style.space(46)
              hasCursor: tsRowHover.hovered
              foreground: root.foreground
              accent: root.accent

              HoverHandler { id: tsRowHover }

              Row {
                anchors.fill: parent
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(10)
                spacing: Style.space(10)

                Column {
                  width: parent.width - tsSwitch.width - Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 0
                  Text {
                    text: service.tailscaleInstalled ? "Tailscale" : "Tailscale (not installed)"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                    width: parent.width
                  }
                  Text {
                    text: service.tailscaleUp ? "Connected" : service.tailscaleDetail
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                    width: parent.width
                  }
                }

                ToggleSwitch {
                  id: tsSwitch
                  anchors.verticalCenter: parent.verticalCenter
                  checked: service.tailscaleUp
                  busy: service.tailscaleBusy
                  interactive: service.tailscaleInstalled
                  foreground: root.foreground
                  accent: root.accent
                  onToggled: service.toggleTailscale()
                }
              }
            }

            // --- Operator mismatch notice: shown proactively (not only
            // after a failed toggle) whenever tailscaled's configured
            // operator isn't the signed-in user, so up/down/login would
            // otherwise silently need sudo. ---
            Column {
              width: parent.width
              spacing: Style.space(2)
              visible: service.tailscaleOperatorMismatch

              Text {
                width: parent.width
                text: "Tailscale operator isn't " + service.tailscaleCurrentUser + " — commands will need sudo."
                wrapMode: Text.Wrap
                color: bar ? bar.urgent : Color.urgent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              Text {
                width: parent.width
                text: "Fix with: " + service.tailscaleOperatorFixCommand
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          // --- OpenVPN section ---
          Column {
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: "OPENVPN (NETWORKMANAGER)"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              visible: service.ovProfiles.length === 0
              width: parent.width
              text: "No OpenVPN/VPN connections found in NetworkManager."
              color: root.dim
              wrapMode: Text.Wrap
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            // --- Import .ovpn profile: opens the desktop file picker (via
            // `omarchy file select`) and hands the chosen file to `nmcli
            // connection import type openvpn`. ---
            Rectangle {
              id: importButton
              width: parent.width
              height: Style.space(36)
              radius: Style.cornerRadius
              color: importMouse.containsMouse && !service.ovImportBusy
                ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
              border.width: Style.normalBorderWidth
              border.color: Style.normalBorderFor(root.foreground, root.accent)
              opacity: service.ovImportBusy ? 0.6 : 1

              Text {
                anchors.centerIn: parent
                text: service.ovImportBusy ? "Choose a profile…" : "Import .ovpn profile…"
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                id: importMouse
                anchors.fill: parent
                hoverEnabled: true
                enabled: !service.ovImportBusy
                cursorShape: Qt.PointingHandCursor
                onClicked: root.importOvProfile()
              }
            }

            // --- Post-import DNS/domain prompt: NetworkManager doesn't
            // import `dhcp-option DNS`/`DOMAIN` lines from the .ovpn file,
            // so ask whether to apply the ones this profile pushed. ---
            Rectangle {
              width: parent.width
              visible: service.importDnsPromptUuid !== ""
              radius: Style.cornerRadius
              color: "transparent"
              border.width: Style.normalBorderWidth
              border.color: root.accent
              height: dnsPromptColumn.implicitHeight + Style.space(20)

              Column {
                id: dnsPromptColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(10)
                spacing: Style.space(6)

                Text {
                  width: parent.width
                  text: "Apply DNS/domain from “" + service.importDnsPromptName + "”?"
                  wrapMode: Text.Wrap
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                }

                Text {
                  width: parent.width
                  visible: service.importDnsList.length > 0
                  text: "DNS: " + service.importDnsList.join(", ")
                  wrapMode: Text.Wrap
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Text {
                  width: parent.width
                  visible: service.importDomainList.length > 0
                  text: "Domain: " + service.importDomainList.join(", ")
                  wrapMode: Text.Wrap
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Text {
                  width: parent.width
                  text: "NetworkManager doesn't import these automatically. Recommended: apply."
                  wrapMode: Text.Wrap
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Row {
                  width: parent.width
                  spacing: Style.space(8)

                  Rectangle {
                    id: dnsSkipButton
                    width: (parent.width - Style.space(8)) / 2
                    height: Style.space(32)
                    radius: Style.cornerRadius
                    color: dnsSkipMouse.containsMouse
                      ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
                    border.width: Style.normalBorderWidth
                    border.color: Style.normalBorderFor(root.foreground, root.accent)

                    Text {
                      anchors.centerIn: parent
                      text: "Skip"
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }

                    MouseArea {
                      id: dnsSkipMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: service.dismissImportDnsPrompt()
                    }
                  }

                  Rectangle {
                    id: dnsApplyButton
                    width: (parent.width - Style.space(8)) / 2
                    height: Style.space(32)
                    radius: Style.cornerRadius
                    color: dnsApplyMouse.containsMouse
                      ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18) : Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.10)
                    border.width: Style.normalBorderWidth
                    border.color: root.accent

                    Text {
                      anchors.centerIn: parent
                      text: "Apply (recommended)"
                      color: root.accent
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }

                    MouseArea {
                      id: dnsApplyMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: service.applyImportedDns()
                    }
                  }
                }
              }
            }

            Repeater {
              model: service.ovProfiles
              delegate: CursorSurface {
                required property var modelData
                readonly property var profile: modelData
                width: content.width
                height: ovDelegateColumn.implicitHeight + Style.space(20)
                hasCursor: ovRowHover.hovered
                foreground: root.foreground
                accent: root.accent

                HoverHandler { id: ovRowHover }

                Column {
                  id: ovDelegateColumn
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(10)
                  spacing: Style.space(6)

                  Row {
                    width: parent.width
                    spacing: Style.space(10)

                    Column {
                      width: parent.width - ovActions.width - ovSwitch.width - Style.space(20)
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: 0
                      Text {
                        text: profile.name
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        elide: Text.ElideRight
                        width: parent.width
                      }
                      Text {
                        text: profile.active ? "Connected" + (profile.device ? " · " + profile.device : "")
                          : (profile.connecting ? "Connecting…" : "Disconnected")
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                        width: parent.width
                      }
                    }

                    Row {
                      id: ovActions
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.space(4)

                      PanelActionButton {
                        iconText: "󰏫"
                        tooltipText: "Rename"
                        foreground: root.foreground
                        hoverColor: root.foreground
                        fontFamily: root.fontFamily
                        enabled: service.ovBusyUuid === "" && !(service.credDialogOpen && service.credUuid === profile.uuid)
                        onClicked: root.requestRename(profile)
                      }

                      PanelActionButton {
                        iconText: "󰆴"
                        tooltipText: "Delete"
                        foreground: root.foreground
                        hoverColor: bar ? bar.urgent : Color.urgent
                        fontFamily: root.fontFamily
                        enabled: service.ovBusyUuid === "" && !(service.credDialogOpen && service.credUuid === profile.uuid)
                        onClicked: root.requestDelete(profile)
                      }
                    }

                    ToggleSwitch {
                      id: ovSwitch
                      anchors.verticalCenter: parent.verticalCenter
                      checked: profile.active
                      busy: service.ovBusyUuid === profile.uuid ||
                        (service.credDialogOpen && service.credUuid === profile.uuid && service.credBusy)
                      interactive: service.ovBusyUuid === "" || service.ovBusyUuid === profile.uuid
                      foreground: root.foreground
                      accent: root.accent
                      onToggled: service.toggleOvProfile(profile)
                    }
                  }

                  // --- inline credential prompt, in the same spot Omarchy's
                  // wifi panel uses for its passphrase prompt: expands below
                  // the row, only the fields this profile actually needs. ---
                  Column {
                    width: parent.width
                    spacing: Style.space(6)
                    visible: service.credDialogOpen && service.credUuid === profile.uuid
                    onVisibleChanged: if (visible) root.credSaveCredentials = true

                    PanelSeparator {
                      foreground: root.foreground
                    }

                    PanelSectionHeader {
                      text: "CREDENTIALS NEEDED"
                      foreground: root.foreground
                      fontFamily: root.fontFamily
                    }

                    Text {
                      visible: service.credError !== ""
                      width: parent.width
                      text: service.credError
                      wrapMode: Text.Wrap
                      color: bar ? bar.urgent : Color.urgent
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }

                    TextField {
                      id: credUserField
                      visible: service.credNeedUsername
                      width: parent.width
                      placeholderText: "Username"
                      text: service.credDialogOpen && service.credUuid === profile.uuid ? service.credExistingUsername : ""
                      foreground: root.foreground
                      accent: root.accent
                      enabled: !service.credBusy
                      Keys.onEscapePressed: service.cancelCredentials()
                      onAccepted: {
                        if (credPassField.visible) credPassField.forceActiveFocus()
                        else if (credKeyField.visible) credKeyField.forceActiveFocus()
                      }
                      onVisibleChanged: if (visible) Qt.callLater(forceActiveFocus)
                    }

                    TextField {
                      id: credPassField
                      visible: service.credNeedPassword
                      width: parent.width
                      placeholderText: "Password"
                      password: true
                      foreground: root.foreground
                      accent: root.accent
                      enabled: !service.credBusy
                      Keys.onEscapePressed: service.cancelCredentials()
                      onAccepted: {
                        if (credKeyField.visible) credKeyField.forceActiveFocus()
                        else credConnectBtn.clicked()
                      }
                      onVisibleChanged: if (visible && !credUserField.visible) Qt.callLater(forceActiveFocus)
                    }

                    TextField {
                      id: credKeyField
                      visible: service.credNeedKeyPassword
                      width: parent.width
                      placeholderText: "Private key password"
                      password: true
                      foreground: root.foreground
                      accent: root.accent
                      enabled: !service.credBusy
                      Keys.onEscapePressed: service.cancelCredentials()
                      onAccepted: credConnectBtn.clicked()
                      onVisibleChanged: if (visible && !credUserField.visible && !credPassField.visible) Qt.callLater(forceActiveFocus)
                    }

                    Toggle {
                      width: parent.width
                      label: "Save credentials"
                      description: "Store them in NetworkManager so you won't be asked again."
                      foreground: root.foreground
                      accent: root.accent
                      fontFamily: root.fontFamily
                      checked: root.credSaveCredentials
                      onClicked: root.credSaveCredentials = !root.credSaveCredentials
                    }

                    Row {
                      anchors.right: parent.right
                      spacing: Style.space(6)

                      Text {
                        visible: service.credBusy
                        text: "Connecting…"
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        anchors.verticalCenter: parent.verticalCenter
                      }

                      PanelActionButton {
                        visible: !service.credBusy
                        iconText: "󰅖"
                        tooltipText: "Cancel"
                        foreground: root.foreground
                        hoverColor: bar ? bar.urgent : Color.urgent
                        fontFamily: root.fontFamily
                        onClicked: service.cancelCredentials()
                      }

                      PanelActionButton {
                        id: credConnectBtn
                        visible: !service.credBusy
                        enabled: (!service.credNeedUsername || credUserField.text.length > 0) &&
                          (!service.credNeedPassword || credPassField.text.length > 0) &&
                          (!service.credNeedKeyPassword || credKeyField.text.length > 0)
                        iconText: "󰄬"
                        tooltipText: "Connect"
                        foreground: root.foreground
                        fontFamily: root.fontFamily
                        onClicked: service.submitCredentials(credUserField.text, credPassField.text, credKeyField.text, root.credSaveCredentials)
                      }
                    }
                  }

                  // --- inline rename prompt, same expand-below-the-row spot
                  // as the credential/delete prompts. ---
                  Column {
                    width: parent.width
                    spacing: Style.space(6)
                    visible: root.renameUuid === profile.uuid

                    PanelSeparator {
                      foreground: root.foreground
                    }

                    PanelSectionHeader {
                      text: "RENAME PROFILE"
                      foreground: root.foreground
                      fontFamily: root.fontFamily
                    }

                    TextField {
                      id: renameField
                      width: parent.width
                      text: root.renameUuid === profile.uuid ? root.renameName : ""
                      foreground: root.foreground
                      accent: root.accent
                      enabled: service.ovBusyUuid === ""
                      Keys.onEscapePressed: root.cancelRename()
                      onTextChanged: if (root.renameUuid === profile.uuid) root.renameName = text
                      onAccepted: root.confirmRename()
                      onVisibleChanged: if (visible) Qt.callLater(function() { forceActiveFocus(); selectAll() })
                    }

                    Row {
                      anchors.right: parent.right
                      spacing: Style.space(6)

                      PanelActionButton {
                        iconText: "󰅖"
                        tooltipText: "Cancel"
                        foreground: root.foreground
                        hoverColor: bar ? bar.urgent : Color.urgent
                        fontFamily: root.fontFamily
                        onClicked: root.cancelRename()
                      }

                      PanelActionButton {
                        enabled: root.renameName.trim() !== "" && root.renameName.trim() !== root.renameOriginalName
                        iconText: "󰄬"
                        tooltipText: "Rename"
                        foreground: root.foreground
                        fontFamily: root.fontFamily
                        onClicked: root.confirmRename()
                      }
                    }
                  }

                  // --- inline delete confirmation ---
                  Column {
                    width: parent.width
                    spacing: Style.space(6)
                    visible: root.pendingDeleteUuid === profile.uuid

                    PanelSeparator {
                      foreground: root.foreground
                    }

                    Text {
                      width: parent.width
                      text: "Delete “" + root.pendingDeleteName + "”? This can't be undone."
                      wrapMode: Text.Wrap
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }

                    Row {
                      anchors.right: parent.right
                      spacing: Style.space(6)

                      PanelActionButton {
                        iconText: "󰅖"
                        tooltipText: "Cancel"
                        foreground: root.foreground
                        hoverColor: root.foreground
                        fontFamily: root.fontFamily
                        onClicked: root.cancelDelete()
                      }

                      PanelActionButton {
                        iconText: "󰆴"
                        tooltipText: "Delete"
                        foreground: root.foreground
                        hoverColor: bar ? bar.urgent : Color.urgent
                        fontFamily: root.fontFamily
                        onClicked: root.confirmDelete()
                      }
                    }
                  }
                }
              }
            }
          }

          // --- STATUS: one place for the state of every active connection,
          // fully decoupled from the toggle rows above and from the
          // credential prompt. Only shows up when something is connected. ---
          Column {
            width: parent.width
            spacing: Style.space(8)
            visible: service.tailscaleUp || service.ovProfiles.some(function(p) { return p.active })

            PanelSectionHeader {
              text: "STATUS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              id: statusColumn
              width: parent.width
              spacing: Style.space(10)

              // --- Tailscale status ---
                Column {
                  width: parent.width
                  spacing: Style.space(4)
                  visible: service.tailscaleUp

                  Text {
                    text: "Tailscale"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                  }

                  Row {
                    width: parent.width
                    spacing: Style.space(6)
                    Text {
                      text: "IP"
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      width: Style.space(70)
                    }
                    Text {
                      text: service.tailscaleIp || "—"
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                      width: parent.width - Style.space(70) - parent.spacing
                    }
                  }

                  Row {
                    width: parent.width
                    spacing: Style.space(6)
                    Text {
                      text: "DNS"
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      width: Style.space(70)
                    }
                    Text {
                      text: service.tailscaleDns || "—"
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                      width: parent.width - Style.space(70) - parent.spacing
                    }
                  }

                  Row {
                    width: parent.width
                    spacing: Style.space(6)
                    Text {
                      text: "Devices"
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      width: Style.space(70)
                    }
                    Text {
                      text: service.tailscaleOnlinePeerCount + "/" + service.tailscalePeerCount + " online"
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      width: parent.width - Style.space(70) - parent.spacing
                    }
                  }

                  Column {
                    width: parent.width
                    leftPadding: Style.space(70) + Style.space(6)
                    spacing: Style.space(2)
                    visible: service.tailscalePeers.length > 0

                    Repeater {
                      model: service.tailscalePeers
                      delegate: Row {
                        required property var modelData
                        width: parent ? parent.width : 0
                        spacing: Style.space(6)

                        Rectangle {
                          width: Style.space(6)
                          height: Style.space(6)
                          radius: width / 2
                          anchors.verticalCenter: parent.verticalCenter
                          color: modelData.online ? root.accent : root.dim
                        }
                        Text {
                          text: modelData.name + (modelData.ip ? " · " + modelData.ip : "")
                          color: modelData.online ? root.foreground : root.dim
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                          elide: Text.ElideRight
                        }
                      }
                    }
                  }
                }

                PanelSeparator {
                  foreground: root.foreground
                  visible: service.tailscaleUp && ovStatusRepeater.count > 0
                }

                // --- OpenVPN status (one block per active profile) ---
                Repeater {
                  id: ovStatusRepeater
                  model: service.ovProfiles.filter(function(p) { return p.active })
                  delegate: Column {
                    id: ovStatusDelegate
                    required property var modelData
                    width: statusColumn.width
                    spacing: Style.space(4)

                    Text {
                      text: ovStatusDelegate.modelData.name
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: true
                      elide: Text.ElideRight
                      width: parent.width
                    }

                    Row {
                      width: parent.width
                      spacing: Style.space(6)
                      Text {
                        text: "IP"
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        width: Style.space(70)
                      }
                      Text {
                        text: ovStatusDelegate.modelData.ip || "—"
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                        width: parent.width - Style.space(70) - parent.spacing
                      }
                    }

                    Row {
                      width: parent.width
                      spacing: Style.space(6)
                      Text {
                        text: "DNS"
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        width: Style.space(70)
                      }
                      Text {
                        text: ovStatusDelegate.modelData.dns || "—"
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                        width: parent.width - Style.space(70) - parent.spacing
                      }
                    }

                    Row {
                      width: parent.width
                      spacing: Style.space(6)
                      Text {
                        text: "Gateway"
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        width: Style.space(70)
                      }
                      Text {
                        text: ovStatusDelegate.modelData.gateway || "—"
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                        width: parent.width - Style.space(70) - parent.spacing
                      }
                    }

                    Row {
                      width: parent.width
                      spacing: Style.space(6)
                      Text {
                        text: "Uptime"
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        width: Style.space(70)
                      }
                      Text {
                        text: service.formatUptime(ovStatusDelegate.modelData.connectedSince)
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                        width: parent.width - Style.space(70) - parent.spacing
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
