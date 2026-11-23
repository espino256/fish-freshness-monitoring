# Android release guide

## First signed APK on Windows

For the first AquaSense release only, run from the project root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/New-AndroidReleaseKey.ps1
flutter build apk --release
```

The helper creates a new RSA release signing key in
`android/app/aquasense-release.jks` and a cryptographically generated password
stored in `android/key.properties`. Passwords are not printed or passed as
command-line arguments. Both files are already ignored by Git; the helper
restricts their Windows permissions to the current user/project owner and refuses to overwrite
either file. If they already exist, skip key generation and build normally.

Back up **both files** securely outside the repository. Future APK updates must
use this same signing key. The properties file contains passwords: do not share
it in chat, screenshots, logs or source control. No password needs to be entered
in the terminal for each subsequent local build.

Expected output: `build/app/outputs/flutter-apk/app-release.apk`.

## Existing signing key or another development machine

Restore your original keystore. Copy `android/key.properties.example` to
`android/key.properties`, and fill its four fields locally using that key's
credentials. Relative `storeFile` paths resolve from `android/app`; absolute
Windows paths should use forward slashes, such as `C:/private/release.jks`.
Do not create a replacement key for an already distributed APK.

## CI or environment-based configuration

The existing process environment variables remain supported:
`ANDROID_KEYSTORE_PATH`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, and
`ANDROID_KEY_PASSWORD`. Nonblank environment values take precedence over the
corresponding local properties. Supply them through protected local/CI settings;
never commit credentials. Release builds still fail when credentials are missing
or the keystore is absent, and never use the debug signing key as a fallback.
Debug builds do not require release credentials.

`ANDROID_APPLICATION_ID` remains an optional package-ID override. Keep the
registered Firebase package/signing-certificate setup consistent when changing
it; this signing fix does not change Firebase configuration or the package ID.

The Java `System::load` / native-access warnings are separate from the signing
failure. They do not supply missing signing credentials and are not the reason
for the reported `AquaSense release signing is required` exception.

## Windows native build cache

This checkout limits Gradle to one worker and disables parallel project execution
to avoid concurrent native-plugin metadata writes on Windows. The first full
release build can take several minutes; subsequent builds reuse compiled outputs.

During repair, native-plugin file locks and incomplete Gradle 8.14 transform
entries were also found. The idle Gradle daemon was stopped, and 36 hash-named
transform directories missing `metadata.bin` were reversibly renamed inside
the transforms cache. Gradle regenerated the entries required by this build.
No model files, source files or signing keys were removed by cache recovery.

## Verification in this checkout (2026-11-23)

- The full release build produced `build/app/outputs/flutter-apk/app-release.apk`
  (129,650,745 bytes, approximately 123.6 MiB).
- A repeated `flutter build apk --release` completed with exit code 0 in
  20.6 seconds and produced the identical verified APK.
- Android SDK `apksigner` verified the APK Signature Scheme v2 signature and
  confirmed that its certificate matches the newly generated local release key.
- All five TFLite files packaged in the APK match their project originals
  byte-for-byte. No runtime/model source or freshness classification was changed.
- A debug task-graph dry run passes with an unavailable release keystore;
  a release task-graph dry run correctly rejects that same missing keystore.
- The first-key helper refuses existing files; keystore and properties are
  private and Git-ignored. No passwords were printed or committed.

Public release-certificate fingerprints (not passwords):

```text
SHA-1:   A82A33A09D82582A6212B10EAEBE758B2148B118
SHA-256: a121702e4efc30ef689f802b82875315d6f850851ae1416d3413d96f20d175df
```

Register the release certificate with the corresponding Firebase Android app
for Google sign-in. This build repair does not change remote Firebase settings.
APK build/signature verification does not establish Android device inference,
live authentication, ESP32 hardware operation, or scientific model validation.
Those checks still require the appropriate device, services and evidence.

Local verification records are kept under ignored `build/qa/`, including
`android_release_build.txt`, `android_release_verification.json`,
`android_apk_signature.txt` and `android_apk_models.json`.
