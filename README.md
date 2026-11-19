# Leviko VPN – Manual server picker fix

This update changes the server selection flow to a dedicated full-screen route instead of an in-page dropdown/dialog. It adds two explicit controls on the home screen: **Fastest location** and **Browse configurations**. The manual list shows the original configuration remark/name, with country/city inferred from the remark and IP lookup as a fallback/enrichment. Search matches config name, country, and city. Selecting a row returns the selected configuration to the home screen.

## Apply
Replace `lib/main.dart` and `pubspec.yaml` in the existing repository. Keep the existing `.github/workflows` folder and other Android project files. Commit, then run the existing GitHub Actions workflow.

## Notes
- The configuration display name is the subscription remark (fragment / VMess `ps` field). If a source config has no remark, it will be shown as unnamed.
- Country inference depends on words/country codes present in the configuration name. IP geolocation may enrich it, but geolocation providers can be inaccurate or unavailable.
- This source has not been built or tested on a physical Android device in this environment. Check the Actions build before installing.
