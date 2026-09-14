import QtQuick
import Quickshell
import Quickshell.Io

// Polls Tailscale and NetworkManager (for OpenVPN profiles) and exposes a
// single merged model. Also handles the OpenVPN secrets flow: when a
// NetworkManager VPN connection needs credentials NetworkManager didn't
// already have cached, we detect the "secrets required" failure, inspect the
// connection's vpn.data to figure out which of username/password/private-key
// password are actually missing, and prompt for just those.
Item {
  id: root

  property int refreshIntervalSec: 10

  property bool tailscaleInstalled: false
  property bool tailscaleUp: false
  property string tailscaleDetail: "Checking…"
  property string tailscaleIp: ""
  property string tailscaleDns: ""
  property int tailscalePeerCount: 0
  property int tailscaleOnlinePeerCount: 0
  property var tailscalePeers: []
  property bool tailscaleBusy: false
  property bool tailscaleNeedsLogin: false

  // --- Operator check: `up`/`down`/`login` need either root or the local
  // user set as the tailscaled operator. We check proactively (via `tailscale
  // debug prefs`, best-effort — silently skipped if that subcommand isn't
  // available) and also react to the permission-denied failure itself, so
  // the guidance shows up either way. ---
  readonly property string tailscaleCurrentUser: Quickshell.env("USER") || ""
  property string tailscaleOperatorUser: ""
  property bool tailscaleOperatorChecked: false
  readonly property bool tailscaleOperatorMismatch: tailscaleOperatorChecked && tailscaleCurrentUser !== "" && tailscaleOperatorUser !== tailscaleCurrentUser
  readonly property string tailscaleOperatorFixCommand: "sudo tailscale set --operator=" + tailscaleCurrentUser

  property var ovProfiles: []
  property string ovBusyUuid: ""
  property string lastError: ""
  readonly property bool ovImportBusy: ovImportProcess.running

  // --- Post-import DNS/domain prompt: NetworkManager's OpenVPN import
  // doesn't carry over `dhcp-option DNS`/`DOMAIN` lines from the client
  // config, so when the just-imported profile has any, we ask before
  // applying them to ipv4.dns/ipv4.dns-search. ---
  property string importDnsPromptUuid: ""
  property string importDnsPromptName: ""
  property var importDnsList: []
  property var importDomainList: []

  // --- Credential prompt state (for OpenVPN/NetworkManager connections) ---
  property bool credDialogOpen: false
  property string credUuid: ""
  property string credProfileName: ""
  property bool credNeedUsername: false
  property bool credNeedPassword: false
  property bool credNeedKeyPassword: false
  property string credExistingUsername: ""
  property string credError: ""
  property bool credBusy: false

  readonly property bool anyConnected: tailscaleUp || ovProfiles.some(function(p) { return p.active })

  // Compact "connected since" duration (e.g. "5m", "1h 12m", "2d 4h") from a
  // unix-epoch timestamp. Recomputed against the wall clock each call, so it
  // only advances when something re-evaluates the binding (the periodic
  // refresh), not continuously — fine for an at-a-glance uptime.
  function formatUptime(sinceEpochSec) {
    if (!sinceEpochSec) return "—"
    var secs = Math.max(0, Math.floor(Date.now() / 1000) - sinceEpochSec)
    var days = Math.floor(secs / 86400)
    var hours = Math.floor((secs % 86400) / 3600)
    var mins = Math.floor((secs % 3600) / 60)
    if (days > 0) return days + "d " + hours + "h"
    if (hours > 0) return hours + "h " + mins + "m"
    if (mins > 0) return mins + "m"
    return secs + "s"
  }

  function refresh() {
    if (!tsStatusProcess.running) {
      tsStatusProcess.running = true
    }
    if (!tsPrefsProcess.running) {
      tsPrefsProcess.running = true
    }
    if (!nmListProcess.running) {
      nmListProcess.running = true
    }
  }

  function toggleTailscale() {
    if (!tailscaleInstalled || tsToggleProcess.running) return
    tailscaleBusy = true
    var action = tailscaleUp ? "down" : (tailscaleNeedsLogin ? "login" : "up")
    tsToggleProcess.command = ["tailscale", action]
    tsToggleProcess.running = true
  }

  function toggleOvProfile(profile) {
    if (ovBusyUuid !== "" || !profile) return
    if (root.credDialogOpen && root.credUuid === profile.uuid) return
    ovBusyUuid = profile.uuid
    var action = profile.active ? "down" : "up"
    ovToggleProcess.direction = action
    ovToggleProcess.currentUuid = profile.uuid
    ovToggleProcess.command = ["nmcli", "connection", action, "uuid", profile.uuid]
    ovToggleProcess.running = true
  }

  function renameOvProfile(uuid, nextName) {
    if (ovBusyUuid !== "" || !uuid || !nextName) return
    ovBusyUuid = uuid
    ovManageProcess.command = ["nmcli", "connection", "modify", "uuid", uuid, "connection.id", nextName]
    ovManageProcess.running = true
  }

  function deleteOvProfile(uuid) {
    if (ovBusyUuid !== "" || !uuid) return
    ovBusyUuid = uuid
    ovManageProcess.command = ["nmcli", "connection", "delete", "uuid", uuid]
    ovManageProcess.running = true
  }

  function requestCredentials(uuid) {
    root._pendingCredUuid = uuid
    ovDetailProcess.command = ["nmcli", "-t", "-f", "vpn.data", "connection", "show", uuid]
    ovDetailProcess.running = true
  }

  function cancelCredentials() {
    root.credDialogOpen = false
    root.credUuid = ""
    root.credError = ""
  }

  // Opens the desktop file picker (via `omarchy file select`) and imports
  // the chosen .ovpn/.conf file as a new NetworkManager connection. The
  // helper script exits 1 both when the user cancels the picker and when
  // nmcli fails, so we only surface an error when stderr actually has
  // something to say.
  function importOvProfile(helperPath) {
    if (ovImportProcess.running) return
    root.lastError = ""
    ovImportProcess.command = [helperPath]
    ovImportProcess.running = true
  }

  function dismissImportDnsPrompt() {
    root.importDnsPromptUuid = ""
    root.importDnsPromptName = ""
    root.importDnsList = []
    root.importDomainList = []
  }

  // Applies the DNS/search-domain values pulled out of the just-imported
  // .ovpn file to the new NetworkManager connection.
  function applyImportedDns() {
    if (ovBusyUuid !== "" || importDnsPromptUuid === "") return
    var uuid = importDnsPromptUuid
    var args = ["nmcli", "connection", "modify", "uuid", uuid]
    if (importDnsList.length > 0) {
      args.push("ipv4.dns")
      args.push(importDnsList.join(" "))
    }
    if (importDomainList.length > 0) {
      args.push("ipv4.dns-search")
      args.push(importDomainList.join(" "))
    }
    root.dismissImportDnsPrompt()
    ovBusyUuid = uuid
    ovManageProcess.command = args
    ovManageProcess.running = true
  }

  // Builds and runs a small shell helper that: optionally sets the (non
  // secret) username on the connection, writes only the secrets that were
  // actually requested to a 0600 temp file, activates the connection with
  // that file, then removes it. Secret values are streamed over stdin so
  // they never appear in the process argument list (visible via /proc or ps
  // to other local users); only the uuid, flags, and username travel as
  // arguments.
  function submitCredentials(username, password, keyPassword) {
    if (root.credUuid === "") return
    var hasPass = root.credNeedPassword && password !== ""
    var hasKey = root.credNeedKeyPassword && keyPassword !== ""
    var stdinLines = []
    if (hasPass) stdinLines.push(password)
    if (hasKey) stdinLines.push(keyPassword)

    var script =
      "set -e\n" +
      "uuid=\"$1\"\n" +
      "haspass=\"$2\"\n" +
      "haskey=\"$3\"\n" +
      "username=\"$4\"\n" +
      "if [ -n \"$username\" ]; then nmcli connection modify \"$uuid\" +vpn.data username=\"$username\" >/dev/null; fi\n" +
      "f=$(mktemp)\n" +
      "chmod 600 \"$f\"\n" +
      "if [ \"$haspass\" = \"1\" ]; then IFS= read -r pass; printf 'vpn.secrets.password:%s\\n' \"$pass\" >> \"$f\"; fi\n" +
      "if [ \"$haskey\" = \"1\" ]; then IFS= read -r keypass; printf 'vpn.secrets.cert-pass:%s\\n' \"$keypass\" >> \"$f\"; fi\n" +
      "nmcli connection up uuid \"$uuid\" passwd-file \"$f\"\n" +
      "rc=$?\n" +
      "rm -f \"$f\"\n" +
      "exit $rc\n"

    root.credBusy = true
    root.credError = ""
    ovCredProcess.pendingStdin = stdinLines.length > 0 ? (stdinLines.join("\n") + "\n") : ""
    ovCredProcess.command = ["bash", "-c", script, "_", root.credUuid, hasPass ? "1" : "0", hasKey ? "1" : "0", (username || "")]
    ovCredProcess.running = true
  }

  property string _pendingCredUuid: ""

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer { id: settleRefresh; interval: 700; onTriggered: root.refresh() }

  Process {
    id: tsStatusProcess
    running: false
    command: ["tailscale", "status", "--json"]
    stdout: StdioCollector { id: tsOut; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.tailscaleInstalled = false
        root.tailscaleUp = false
        root.tailscaleDetail = "Not installed or unreachable"
        root.tailscaleIp = ""
        root.tailscaleDns = ""
        root.tailscalePeerCount = 0
        root.tailscaleOnlinePeerCount = 0
        root.tailscalePeers = []
        return
      }
      root.tailscaleInstalled = true
      try {
        var data = JSON.parse(tsOut.text)
        root.tailscaleUp = data.BackendState === "Running"
        root.tailscaleNeedsLogin = data.BackendState === "NeedsLogin"
        var dnsName = (data.Self && data.Self.DNSName) ? String(data.Self.DNSName).replace(/\.$/, "") : ""
        root.tailscaleDetail = data.BackendState === "Running"
          ? "Connected" + (dnsName ? " · " + dnsName : "")
          : data.BackendState === "NeedsLogin"
          ? "Not logged in"
          : (data.BackendState || "Unknown")
        root.tailscaleIp = (data.Self && data.Self.TailscaleIPs && data.Self.TailscaleIPs.length > 0)
          ? data.Self.TailscaleIPs[0] : ""
        root.tailscaleDns = dnsName
        var peers = data.Peer || {}
        var total = 0, online = 0
        var peerList = []
        for (var k in peers) {
          var peer = peers[k]
          if (!peer) continue
          total++
          if (peer.Online) online++
          var pname = peer.DNSName ? String(peer.DNSName).replace(/\.$/, "").split(".")[0] : (peer.HostName || "unknown")
          peerList.push({
            name: pname,
            ip: (peer.TailscaleIPs && peer.TailscaleIPs.length > 0) ? peer.TailscaleIPs[0] : "",
            online: !!peer.Online
          })
        }
        peerList.sort(function(a, b) {
          if (a.online !== b.online) return a.online ? -1 : 1
          return a.name.localeCompare(b.name)
        })
        root.tailscalePeerCount = total
        root.tailscaleOnlinePeerCount = online
        root.tailscalePeers = peerList
      } catch (e) {
        root.tailscaleUp = false
        root.tailscaleDetail = "Status parse error"
        root.tailscaleIp = ""
        root.tailscaleDns = ""
        root.tailscalePeerCount = 0
        root.tailscaleOnlinePeerCount = 0
        root.tailscalePeers = []
      }
    }
  }

  // Best-effort, read-only check of who tailscaled considers its operator
  // (the user allowed to run up/down/login without sudo). `debug prefs` is
  // an undocumented but stable subcommand; if a given tailscale build
  // doesn't have it, this just fails quietly and we fall back to catching
  // the permission error reactively in tsToggleProcess below.
  Process {
    id: tsPrefsProcess
    running: false
    command: ["tailscale", "debug", "prefs"]
    stdout: StdioCollector { id: tsPrefsOut; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) return
      try {
        var prefs = JSON.parse(tsPrefsOut.text)
        root.tailscaleOperatorUser = prefs.OperatorUser || ""
        root.tailscaleOperatorChecked = true
      } catch (e) {
        // leave last-known state alone
      }
    }
  }

  Process {
    id: tsToggleProcess
    running: false
    command: []
    stderr: StdioCollector { id: tsToggleErr; waitForEnd: true }
    onExited: function(exitCode) {
      root.tailscaleBusy = false
      if (exitCode !== 0) {
        var errText = String(tsToggleErr.text || "").trim()
        if (/operator|access denied|must be root|permission denied/i.test(errText)) {
          root.lastError = "Tailscale: você não é o operator configurado. " +
            "Rode no terminal: " + root.tailscaleOperatorFixCommand
        } else {
          root.lastError = "Tailscale: " + (errText || "command failed")
        }
      } else {
        root.lastError = ""
      }
      settleRefresh.restart()
    }
  }

  // NAME can contain ":"; --escape yes backslash-escapes it so the split
  // below is safe as long as fields don't contain a literal "\:" sequence.
  Process {
    id: nmListProcess
    running: false
    command: ["nmcli", "-t", "--escape", "yes", "-f", "UUID,NAME,TYPE,DEVICE,STATE", "connection", "show"]
    stdout: StdioCollector { id: nmOut; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) { root.ovProfiles = []; return }
      var lines = String(nmOut.text || "").split("\n")
      var profiles = []
      for (var i = 0; i < lines.length; i++) {
        var line = lines[i]
        if (line === "") continue
        var parts = line.split(":")
        if (parts.length < 5) continue
        var type = parts[2]
        if (type !== "vpn" && type !== "wireguard") continue
        profiles.push({
          uuid: parts[0],
          name: parts[1].replace(/\\:/g, ":"),
          type: type,
          device: parts[3],
          active: parts[4] === "activated",
          connecting: parts[4] === "activating",
          ip: "",
          dns: "",
          gateway: "",
          connectedSince: 0
        })
      }
      root.ovProfiles = profiles

      // Queried per-connection (not per-device): the device's own IP4 config
      // can end up carrying the merged, system-wide resolver (e.g. the wifi's
      // DNS) rather than what this VPN itself pushed, especially without
      // split-DNS. `connection show <uuid>` reports the applied IP4 config
      // for that specific active connection, so it stays scoped to the VPN.
      var activeUuids = profiles.filter(function(p) { return p.active && /^[A-Za-z0-9-]+$/.test(p.uuid) }).map(function(p) { return p.uuid })
      if (activeUuids.length > 0) {
        var script = activeUuids.map(function(u) {
          return "printf '%s\\t%s\\t%s\\t%s\\t%s\\n' '" + u + "'" +
            " \"$(nmcli -g IP4.ADDRESS connection show '" + u + "' 2>/dev/null | head -1)\"" +
            " \"$(nmcli -g IP4.DNS connection show '" + u + "' 2>/dev/null | paste -sd, -)\"" +
            " \"$(nmcli -g IP4.GATEWAY connection show '" + u + "' 2>/dev/null | head -1)\"" +
            " \"$(nmcli -g connection.timestamp connection show '" + u + "' 2>/dev/null | head -1)\""
        }).join("\n")
        ovIpProcess.command = ["bash", "-c", script]
        ovIpProcess.running = true
      }
    }
  }

  Process {
    id: ovIpProcess
    running: false
    command: []
    stdout: StdioCollector { id: ovIpOut; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) return
      var ipMap = {}, dnsMap = {}, gatewayMap = {}, sinceMap = {}
      String(ovIpOut.text || "").split("\n").forEach(function(line) {
        if (!line) return
        var cols = line.split("\t")
        if (cols.length < 1) return
        ipMap[cols[0]] = (cols[1] || "").trim()
        dnsMap[cols[0]] = (cols[2] || "").trim()
        gatewayMap[cols[0]] = (cols[3] || "").trim()
        sinceMap[cols[0]] = parseInt((cols[4] || "").trim(), 10) || 0
      })
      root.ovProfiles = root.ovProfiles.map(function(p) {
        if (ipMap[p.uuid] || dnsMap[p.uuid] || gatewayMap[p.uuid] || sinceMap[p.uuid]) {
          var np = Object.assign({}, p)
          if (ipMap[p.uuid]) np.ip = ipMap[p.uuid]
          if (dnsMap[p.uuid]) np.dns = dnsMap[p.uuid]
          if (gatewayMap[p.uuid]) np.gateway = gatewayMap[p.uuid]
          if (sinceMap[p.uuid]) np.connectedSince = sinceMap[p.uuid]
          return np
        }
        return p
      })
    }
  }

  Process {
    id: ovToggleProcess
    running: false
    property string direction: ""
    property string currentUuid: ""
    property bool timedOut: false
    command: []
    stderr: StdioCollector { id: ovToggleErr; waitForEnd: true }
    onStarted: {
      timedOut = false
      ovToggleDeadline.restart()
    }
    onExited: function(exitCode) {
      ovToggleDeadline.stop()
      ovToggleKillDelay.stop()
      root.ovBusyUuid = ""
      if (exitCode !== 0) {
        var errText = String(ovToggleErr.text || "").trim()
        if (timedOut) {
          root.lastError = "OpenVPN: connection attempt timed out"
        } else if (direction === "up" && /secret/i.test(errText)) {
          root.lastError = ""
          root.requestCredentials(currentUuid)
        } else {
          root.lastError = "OpenVPN: " + (errText || "command failed")
        }
      } else {
        root.lastError = ""
      }
      settleRefresh.restart()
    }
  }

  Process {
    id: ovManageProcess
    running: false
    command: []
    stderr: StdioCollector { id: ovManageErr; waitForEnd: true }
    onExited: function(exitCode) {
      root.ovBusyUuid = ""
      if (exitCode !== 0) {
        var errText = String(ovManageErr.text || "").trim()
        root.lastError = "OpenVPN: " + (errText || "command failed")
      } else {
        root.lastError = ""
      }
      settleRefresh.restart()
    }
  }

  Process {
    id: ovImportProcess
    running: false
    command: []
    stdout: StdioCollector { id: ovImportOut; waitForEnd: true }
    stderr: StdioCollector { id: ovImportErr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        var errText = String(ovImportErr.text || "").trim()
        if (errText !== "") root.lastError = "Import: " + errText
      } else {
        root.lastError = ""
        var fields = {}
        String(ovImportOut.text || "").split("\n").forEach(function(line) {
          var tab = line.indexOf("\t")
          if (tab < 0) return
          fields[line.substring(0, tab)] = line.substring(tab + 1)
        })
        var dns = String(fields.DNS || "").trim()
        var domains = String(fields.DOMAINS || "").trim()
        if (fields.UUID && (dns !== "" || domains !== "")) {
          root.importDnsPromptUuid = fields.UUID
          root.importDnsPromptName = fields.NAME || fields.UUID
          root.importDnsList = dns === "" ? [] : dns.split(/\s+/)
          root.importDomainList = domains === "" ? [] : domains.split(/\s+/)
        }
      }
      settleRefresh.restart()
    }
  }

  Process {
    id: ovDetailProcess
    running: false
    command: []
    stdout: StdioCollector { id: ovDetailOut; waitForEnd: true }
    onExited: function(exitCode) {
      // Ask only for what NetworkManager doesn't already have stored for
      // this profile. Secret flags: 0 = saved in the system connection (NM
      // already has it, don't ask), 1 = agent-owned, 2 = never saved (both
      // mean "ask every time"), 4 = not-required bit (this profile doesn't
      // use that secret at all). Whether a username is needed at all is a
      // property of the auth type ("password"/"password-tls" always need
      // one), not just of whether vpn.data happens to already have a
      // "username" key — a freshly imported .ovpn profile usually has no
      // "username" key yet even though the auth type requires one. Fall
      // back to asking for everything only if vpn.data couldn't be read at
      // all, since then we genuinely don't know what's missing.
      var needUser = true, needPass = true, needKey = true, existingUser = ""
      if (exitCode === 0) {
        var text = String(ovDetailOut.text || "")
        var idx = text.indexOf(":")
        var body = idx >= 0 ? text.substring(idx + 1) : text
        var fields = {}
        body.split(",").forEach(function(kv) {
          var t = kv.trim()
          if (!t) return
          var eq = t.indexOf("=")
          if (eq < 0) return
          fields[t.substring(0, eq).trim()] = t.substring(eq + 1).trim()
        })
        var NOT_REQUIRED = 4
        var ASK_EVERY_TIME = 1 | 2 // AGENT_OWNED | NOT_SAVED
        var connType = fields.hasOwnProperty("connection-type") ? fields["connection-type"] : ""
        var passwordAuth = connType === "password" || connType === "password-tls"
        existingUser = fields.hasOwnProperty("username") ? fields["username"] : ""
        needUser = existingUser === "" && (passwordAuth || fields.hasOwnProperty("username"))
        var passFlags = fields.hasOwnProperty("password-flags") ? parseInt(fields["password-flags"], 10) : NaN
        var keyFlags = fields.hasOwnProperty("cert-pass-flags") ? parseInt(fields["cert-pass-flags"], 10) : NaN
        needPass = !isNaN(passFlags) && (passFlags & NOT_REQUIRED) === 0 && (passFlags & ASK_EVERY_TIME) !== 0
        needKey = !isNaN(keyFlags) && (keyFlags & NOT_REQUIRED) === 0 && (keyFlags & ASK_EVERY_TIME) !== 0
      }
      var uuid = root._pendingCredUuid
      var profile = root.ovProfiles.find(function(p) { return p.uuid === uuid })
      root.credUuid = uuid
      root.credProfileName = profile ? profile.name : uuid
      root.credExistingUsername = existingUser
      root.credNeedUsername = needUser
      root.credNeedPassword = needPass
      root.credNeedKeyPassword = needKey
      root.credError = ""
      root.credBusy = false
      root.credDialogOpen = true
    }
  }

  Process {
    id: ovCredProcess
    running: false
    stdinEnabled: true
    property string pendingStdin: ""
    property bool timedOut: false
    command: []
    stdout: StdioCollector { id: ovCredOut; waitForEnd: true }
    stderr: StdioCollector { id: ovCredErr; waitForEnd: true }
    onStarted: {
      timedOut = false
      ovCredDeadline.restart()
      if (pendingStdin !== "") {
        write(pendingStdin)
        pendingStdin = ""
      }
    }
    onExited: function(exitCode) {
      ovCredDeadline.stop()
      ovCredKillDelay.stop()
      root.credBusy = false
      if (exitCode === 0) {
        root.credDialogOpen = false
        root.credUuid = ""
        root.credError = ""
        root.lastError = ""
      } else {
        root.credError = timedOut
          ? "Connection attempt timed out. Check your credentials and try again."
          : String(ovCredErr.text || "Authentication failed").trim()
      }
      settleRefresh.restart()
    }
  }

  // Safety nets: if `nmcli connection up` hangs (e.g. the server never
  // responds to bad/missing credentials) these keep the widget from getting
  // stuck showing a spinner forever — SIGTERM first, SIGKILL a second later
  // if that alone didn't stop it.
  Timer {
    id: ovToggleDeadline
    interval: 30000
    onTriggered: {
      if (!ovToggleProcess.running) return
      ovToggleProcess.timedOut = true
      ovToggleProcess.signal(15)
      ovToggleKillDelay.restart()
    }
  }
  Timer { id: ovToggleKillDelay; interval: 1000; onTriggered: if (ovToggleProcess.running) ovToggleProcess.signal(9) }

  Timer {
    id: ovCredDeadline
    interval: 30000
    onTriggered: {
      if (!ovCredProcess.running) return
      ovCredProcess.timedOut = true
      ovCredProcess.signal(15)
      ovCredKillDelay.restart()
    }
  }
  Timer { id: ovCredKillDelay; interval: 1000; onTriggered: if (ovCredProcess.running) ovCredProcess.signal(9) }
}
