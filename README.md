# LEVIKO VPN

Flutter Android VPN client using `v2ray_box` with the Xray engine selected at startup.

## Build with GitHub Actions

The repository contains `.github/workflows/build-apk.yml`. Push the complete repository to the `main` branch or run **Build LEVIKO VPN APK** manually from GitHub Actions.

The workflow:
1. Creates the Android platform project.
2. Installs Java, Flutter, Go, Android SDK and NDK.
3. Downloads the `v2ray_box` 1.0.6 Android Xray build script.
4. Patches the generated compatibility wrapper to remove its obsolete `nodep.CallResponse` reference, which is no longer present in the current XTLS/libXray API.
5. Builds and verifies `android/app/libs/libxray.aar`.
6. Builds the release APK, uploads it as an Actions artifact, and publishes a GitHub release.

`libxray.aar` is generated during CI and is intentionally not committed to the repository.

## Important testing note

A green GitHub Actions build confirms that the APK compiled and the native library was packaged. It does not prove that every subscription format or server works. After installing the APK, test it with known-good VLESS, VMess, Trojan or Shadowsocks profiles and check actual data transfer.

The project source archive does not include a prebuilt APK. The APK is produced by GitHub Actions.
