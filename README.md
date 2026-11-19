# Leviko VPN - UI hotfix source

This package updates the Flutter UI source for the existing Leviko VPN project.

## Changes in this hotfix
- Server picker changed to a modal dialog with explicit close/search/favorites controls.
- The server selector is now an InkWell row with a larger tap target.
- The animated globe/map layer is positioned behind the shield, connection status, timer, and Connect/Disconnect button (not used as the button itself).
- Existing sing-box connection and traffic-statistics code is retained.

## Apply
Replace `lib/main.dart` and `pubspec.yaml` in the GitHub repository with the files in this package. Keep the existing `.github/workflows` folder. Commit the changes, then run the GitHub Actions workflow.

## Important
The globe is currently a lightweight stylized offline illustration with a marker based on the selected server's IP geolocation. It is not yet a precise cartographic map with official country-border polygons. The source was not built on a physical Android device in this environment; verify the GitHub Actions build before installing.
