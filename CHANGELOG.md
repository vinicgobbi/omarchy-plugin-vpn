## v0.1.1 (2026-09-26)

### Fix

- pede a senha da chave privada quando o perfil OpenVPN importado tem chave criptografada sem cert-pass-flags
- força textFormat: Text.PlainText em dados externos (nomes de perfil importado, peers do Tailscale, DNS/IP)
- declara homepage e padroniza author (vinicgobbi) no manifest
- disable qmllint's alias category too
- match bar icon color to the bar's own fading foreground
- stop panel text from fading to invisible with the bar
- close credential-handling gaps from security review (4210e1f)

### Refactor

- usa Util.alpha() em vez de Qt.rgba(x.r,x.g,x.b,N) na mão
- remove scripts/dev-install e dev-uninstall, adota git clone + remote como os outros plugins

## v0.1.0 (2026-09-14)

### Feat

- add save-credentials toggle to the OpenVPN credential prompt
- offer to apply imported DNS/domain settings
- rename and delete OpenVPN profiles
- import OpenVPN profiles from .ovpn files
- initial VPN Manager Omarchy plugin

### Fix

- let the panel grow to fill available screen space
- use theme-aware corner radius and border tokens
- translate remaining Portuguese strings to English
- correct OpenVPN username detection and stuck-connecting state

### Refactor

- flatten card rows to match native panel list style
- use PanelSectionHeader and PanelSeparator components
