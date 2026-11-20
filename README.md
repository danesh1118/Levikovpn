# LEVIKO VPN — Xray-core migration

This source version replaces the previous `sing_box` Flutter dependency with `v2ray_box` and explicitly selects `Xray-core` at startup. The UI, subscription loading, server list, favorites, update checker, and existing display logic are retained.

## Important Android build requirement

The `v2ray_box` package does not bundle native core files in its published package. An Android build must include the Xray AAR at `android/app/libs/libxray.aar`, plus the plugin's Android VPN service declaration and Gradle configuration. The original ZIP supplied for this migration did not include an `android/` project directory; its GitHub Actions workflow generates one during CI.

Therefore this archive is a migrated Flutter source project, **not a tested APK**. A successful release build and real-device VPN test are still required before distributing it.

## Core API

- Core engine: Xray-core (`setCoreEngine('xray')`)
- Connection: original share link passed to `V2rayBox.connect`
- Status: `watchStatus()`
- Traffic: `watchStats()`
- Alerts: `watchAlerts()`

The published plugin documents Android Xray integration through `libxray.aar` and the `VPNService` declaration. See the package documentation for the matching setup instructions.
