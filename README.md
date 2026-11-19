# Leviko VPN — Updated Android source

## Included changes
- Dark premium purple interface with a cleaner home screen.
- Server list moved into a bottom-sheet window; raw configuration remarks/IDs are not displayed.
- Server city/country lookup using the server hostname's resolved IP via ipwho.is; country flag is generated from the returned ISO country code. If lookup fails, the subscription remark is used as a fallback.
- Live upload/download speed and total traffic cards using sing-box traffic statistics.
- Fastest server selection, TCP latency display, Persian/English UI, Telegram channel button.
- Supports VLESS, VMess, Trojan and Shadowsocks links only.

## Build
Use Flutter 3.44+ (the GitHub workflow can use Flutter stable 3.50), JDK 17+, and Android SDK.

```bash
flutter pub get
flutter create . --platforms=android
flutter build apk --release --split-per-abi
```

The smaller device-specific APKs are created under `build/app/outputs/flutter-apk/`.

## Important limitations
- This source has been updated, but it has **not been built or tested on a physical Android phone in this environment**. Run a new GitHub Actions build and test the APK before distributing it.
- City/country is inferred from the server hostname's public IP using a third-party geolocation service. This can show the hosting/CDN location rather than the VPN exit location; city data may be unavailable. If lookup fails, the app falls back to the subscription remark. No geolocation provider can guarantee every server has a city result.
- The latency shown is a TCP handshake estimate, not a real end-to-end VPN latency test. The upload/download cards show the sing-box core's live traffic counters; if both remain zero after connecting, inspect sing-box logs and verify the selected subscription node is reachable and correctly configured. A VPN permission dialog and a connected system icon alone do not prove the proxy is passing traffic.
- The app's connect call delegates configuration validation and tunnel creation to sing-box. Incorrect credentials, unsupported transports (for example XHTTP), server-side ACLs, DNS issues, or unreachable endpoints can still result in no traffic.
- The subscription URL is embedded in the app and is public. Hiding it in the UI does not make it secret; the selected link must be present on-device for the tunnel to work. Use an authenticated backend with short-lived tokens if access control is required.
- `sing_box` and the sing-box core are GPL-3.0-or-later. Comply with the license and include the complete corresponding source/notices when distributing the app.

## Subscription
Configured in `lib/main.dart`:
`https://raw.githubusercontent.com/danesh1118/SS/refs/heads/main/CC`

## Telegram
`https://t.me/Leviko_v2ray`
