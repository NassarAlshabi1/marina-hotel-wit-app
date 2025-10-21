# Marina Hotel Mobile

## Google Sign-In and Drive backup
- Firebase project: `aden-flutter` (project number `256666337807`).
- Android package name: `com.aden.marina`.
- `google-services.json` is located under `android/app/` and includes the Android OAuth client (`256666337807-vjto7nr7vhrrees1f5j9v2h4vdicmd43.apps.googleusercontent.com`).
- The Drive backup flow uses the default `GoogleSignIn` instance in `lib/services/drive_backup_service.dart`, so no hard-coded client ID is necessary.

### Rotating credentials
1. Register a new Android app for `com.aden.marina` in Firebase and upload its SHA-1 and SHA-256 fingerprints.
2. Run `flutterfire configure --project=aden-flutter --android-package-name=com.aden.marina` and replace `android/app/google-services.json` with the generated file.
3. Commit only the regenerated JSON. Keep keystore files and secrets out of source control.

### Smoke test checklist
1. Ensure an Android device or emulator is signed in with a Google account.
2. Launch the Drive backup screen, tap “Sign in with Google”, and confirm the account email appears in the status card.
3. Tap “نسخة احتياطية الآن” and verify a new item is pushed to the Drive `appDataFolder` without errors.
4. Check the in-app status to confirm the last-backup timestamp updates.

### Platform notes
- For the web build, pass the associated web client ID when constructing `GoogleSignIn` (e.g. `GoogleSignIn(clientId: '<web-client-id>')`).
- iOS builds require the corresponding GoogleService-Info.plist from the same Firebase project and a matching reversed client ID in the URL types.
