# Leviko VPN — Updated Android source

## Changes in this build
- Server list opens in a larger, searchable bottom sheet with All/Favorites filters.
- Favorite servers are saved locally on the device.
- Subscription nodes appear as soon as the subscription is parsed; TCP ping and IP geolocation run in parallel background batches instead of blocking the first screen.
- Refresh button and pull-to-refresh for the subscription.
- Animated lightweight globe background with a highlighted server marker based on the selected node's IP geolocation coordinates.
- Connection session timer and live sing-box upload/download statistics.
- Fastest-server selection, TCP latency display, Persian/English UI, Telegram channel button.
- Supports VLESS, VMess, Trojan and Shadowsocks links only.

## Build
```bash
flutter pub get
flutter create . --platforms=android
flutter build apk --release --split-per-abi
```

## Important technical notes
- The globe is an offline lightweight stylized globe, not a full GIS country-boundary map. Its marker uses IP geolocation coordinates. IP geolocation can identify a hosting/CDN address rather than the actual VPN exit location, and some providers return incomplete data.
- The highlighted oval is a visual location marker, not an official country border. Accurate country borders require a separate geographic boundary dataset.
- Server list loading is no longer blocked by ping/geolocation calls. Initial display still depends on the subscription URL responding. Geolocation is best-effort and continues in the background.
- Ping is a TCP connection-time estimate, not a full VPN throughput test.
- The live traffic counters are provided by sing-box. A connected status alone does not guarantee traffic is flowing.
- This source has not been built or tested on a physical Android device in this environment. Run GitHub Actions and test the generated APK before distribution.
- Kill switch, split tunneling, ad/tracker blocking, and automatic reconnect are not presented as active features here because they need dedicated native/engine integration and testing; the UI does not pretend these are enabled.
- The subscription URL is embedded in the app and is public. Hiding it in the UI does not make it secret.
- `sing_box` and its core are GPL-3.0-or-later. Follow the license requirements when distributing the app.
