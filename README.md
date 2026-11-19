# Leviko VPN – server list display and diagnostics update

## Changes
- Server cards now show the detected city as the main title (for example, Frankfurt), with the flag kept at the left. The subscription remark/config name is no longer rendered.
- The selected-server label on the home screen also shows the city/location instead of the config remark.
- Ping colors are: 1–99 ms blue, 100–199 ms green, 200–499 ms yellow, 500+ ms red.
- Added a listener for sing-box runtime connection errors so a tunnel that starts and then fails can show the core error in the app instead of only showing a generic connected state.
- The app continues to pass the original share link to sing-box, preserving protocol-specific parameters such as TLS, Reality, Vision, transport, SNI and fingerprint options when present in the link.

## Protocol support and limits
The configured `sing_box` dependency documents support for VLESS, VMess, Trojan and Shadowsocks links, including common TLS/Reality/Vision and transport settings supported by the bundled sing-box core. Not every possible third-party config format or extension is supported (for example XHTTP, mKCP and ShadowsocksR are listed as unsupported by that core). A server can also fail because its endpoint, credentials, DNS, network, or server-side configuration is invalid.

## Important about the no-traffic issue
This source-only archive adds runtime error reporting, but it cannot prove that traffic works without the full Android project and a real-device test using a valid server profile. If the tunnel says Connected but traffic remains at zero, the sing-box core logs and the exact profile are needed to identify whether the cause is routing, DNS, server reachability, or invalid credentials. Do not treat the connected label alone as proof that the proxy is carrying traffic.

## Ping accuracy
The displayed pre-connection value is a TCP handshake-time estimate. It is not ICMP ping or end-to-end proxy latency. Values are kept real; dividing 200 ms to display 100 ms would be misleading and would not make the connection faster.

## Apply
1. Extract this ZIP.
2. Replace `lib/main.dart` in the existing Flutter repository with `Leviko_VPN_Updated/lib/main.dart`.
3. Keep the existing Android project files.
4. Build and test on an Android device.

This archive has not been built or tested on a physical Android device in this environment.
