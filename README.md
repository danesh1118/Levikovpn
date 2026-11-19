# Leviko VPN — Android Flutter project

## Included
- Persian / English interface.
- Black + neon-purple visual style.
- Fixed subscription URL configured in `lib/main.dart`.
- Server names/locations shown without displaying share links or IDs.
- TCP latency check and fastest-server selection.
- VPN connect/disconnect through the `sing_box` Flutter package.
- Telegram channel promo panel.

## Build
Requirements: Flutter stable, Android SDK, JDK 17 or newer.

```bash
flutter pub get
flutter create . --platforms=android
flutter run
```

To build a release APK:
```bash
flutter build apk --release
```

For smaller device-specific APKs:
```bash
flutter build apk --split-per-abi --release
```

## Important implementation notes
1. The subscription URL is a public raw GitHub file. Anyone who obtains it can read its contents. Hiding it in the app UI does not make it secret. For real protection, proxy subscription access through an authenticated backend and issue short-lived user tokens.
2. The app never renders the raw share links in its UI, but the VPN core must receive a selected link on-device to establish the tunnel. A technically determined user can inspect app memory/network traffic on a rooted or instrumented device.
3. The current subscription was inspected during project preparation and contained VLESS and Shadowsocks links. The app filters VLESS, VMess, Trojan, Shadowsocks and WireGuard share links. OpenVPN `.ovpn` profiles are not supported by sing-box and need a separate OpenVPN engine/integration.
4. The location label is inferred from the server remark/flag in the subscription. This first version does not perform third-party IP geolocation lookups. Ping is a TCP connection-time estimate, not an ICMP ping and not a full throughput test.
5. `sing_box` and sing-box are GPL-3.0-or-later. If distributing an app that bundles this engine, comply with the applicable GPL source and notices requirements. See package documentation:
   https://pub.dev/packages/sing_box
6. The Telegram button opens `https://t.me/Leviko_v2ray` using `url_launcher`.

## Security
Do not commit private subscription URLs or user credentials into a public repository. The configured URL is already public by design.
