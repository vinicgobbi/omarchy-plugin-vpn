import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "vinicgobbi.vpn"
  ipcTarget: "vinicgobbi.vpn"

  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color accent: Color.accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property int refreshIntervalSec: {
    var n = parseInt(String(setting("refreshIntervalSec", 10)), 10)
    return (isFinite(n)) ? Math.max(3, Math.min(300, n)) : 10
  }

  readonly property string vpnIcon: "󰖂"
  readonly property color iconColor: service.anyConnected ? foreground : dim
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

  function importOvProfile() {
    service.importOvProfile(root.bundledPath("import-profile"))
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
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(420))

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

            Text {
              text: "TAILSCALE"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.1
            }

            Rectangle {
              width: parent.width
              height: Style.space(46)
              radius: Style.space(4)
              color: "transparent"
              border.width: 1
              border.color: root.dim

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
                text: "Operator do Tailscale não é " + service.tailscaleCurrentUser + " — comandos vão pedir sudo."
                wrapMode: Text.Wrap
                color: bar ? bar.urgent : Color.urgent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              Text {
                width: parent.width
                text: "Corrija com: " + service.tailscaleOperatorFixCommand
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

            Text {
              text: "OPENVPN (NetworkManager)"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.1
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
              radius: Style.space(4)
              color: importMouse.containsMouse && !service.ovImportBusy
                ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10) : "transparent"
              border.width: 1
              border.color: root.dim
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

            Repeater {
              model: service.ovProfiles
              delegate: Rectangle {
                required property var modelData
                readonly property var profile: modelData
                width: content.width
                height: ovDelegateColumn.implicitHeight + Style.space(20)
                radius: Style.space(4)
                color: "transparent"
                border.width: 1
                border.color: root.dim

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
                      width: parent.width - ovSwitch.width - Style.space(10)
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

                    ToggleSwitch {
                      id: ovSwitch
                      anchors.verticalCenter: parent.verticalCenter
                      checked: profile.active
                      busy: service.ovBusyUuid === profile.uuid || (service.credDialogOpen && service.credUuid === profile.uuid)
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

                    Rectangle {
                      width: parent.width
                      height: 1
                      color: root.dim
                      opacity: 0.4
                    }

                    Text {
                      text: "Credentials needed"
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                      font.letterSpacing: 1.1
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
                        onClicked: service.submitCredentials(credUserField.text, credPassField.text, credKeyField.text)
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

            Text {
              text: "STATUS"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.1
            }

            Rectangle {
              width: parent.width
              radius: Style.space(4)
              color: "transparent"
              border.width: 1
              border.color: root.dim
              height: statusColumn.implicitHeight + Style.space(20)

              Column {
                id: statusColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(10)
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

                Rectangle {
                  width: parent.width
                  height: 1
                  color: root.dim
                  opacity: 0.4
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
}
