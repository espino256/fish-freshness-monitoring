# AquaSense — Mobile-Based Fish Freshness Monitoring

Flutter application plus ESP32 DevKit V1 pH firmware and AI Thinker ESP32-CAM firmware. All authentication is live Firebase: registration, email/password login, Google login, password reset, verification and sign-out. There is no simulated sign-in, local account, guest login or authentication bypass.

## Start here

Requirements: Flutter 3.38.6 / Dart 3.10.7 or compatible newer SDK and a configured Firebase project with Email/Password Authentication, Realtime Database and Cloud Storage. Enable Google Authentication if using the Google button. ESP32 boards are needed for live telemetry/video. Node 22+ and Java 21 are needed for administrative tools and emulator tests.

```powershell
flutter pub get
Copy-Item .env.example .env
# Fill .env locally with the Firebase app registered for your platform.
powershell -ExecutionPolicy Bypass -File scripts/Build-Config.ps1
firebase deploy --project YOUR_PROJECT_ID --only database,storage
flutter run --dart-define-from-file=config/firebase.local.json
```

A branded splash runs for 2.5 seconds at startup. If Firebase startup fails or times out, the app stays on the login screen with a connection/setup message. Auth actions retry initialization and show errors without granting access. Successful sign-in or account creation immediately opens AppShell with the active Firebase UID and clears pushed authentication routes, without waiting for an auth-stream event. Display preferences cannot authenticate a user.

Registration has only Full name, Email address, Password and Confirm Password. It creates the Firebase Auth user, updates the Auth display name, saves displayName/email/createdAt under /users/{uid}, and sends verification. No role/category is selected or assigned by the client. Inspector privileges are still administrator-managed custom claims.

The authenticated workspace has Dashboard, Camera & HSV, History and Settings, with responsive mobile navigation and a desktop sidebar. Dashboard subscribes to real telemetry, marks readings stale after 20 seconds, and displays pH, averaged ADC count and nominal/calibrated voltage. History loads the most recent 500 pH and 500 image records; tables show 50 matching rows, while filtered CSV includes the entire loaded window. Settings offers connection refresh, display contrast and About. No simulation controls or guest-session shortcuts are exposed by the production app.

Shared SoftPanel, SoftField, SoftButton, AuthLayout and OceanBackdrop widgets preserve Neumorphic highlights/shadows, pressed/busy states, readable ocean colors and the bundled water background. [UI design notes](docs/ui-design.md) record the image asset and prompt. Synthetic sensor/image fixtures remain available only for component tests, independently of authentication; production AquaSenseApp does not install their scope or create local identities.
## Configuration and security

Registration always calls `FirebaseAuth.createUserWithEmailAndPassword`. A successful
Auth request immediately creates the account in the Firebase Console, even before
email verification. Firebase automatically signs in the new account. Profile saving
and verification delivery finish in the background after entry to the dashboard.
If either fails, a dashboard notice and Snackbar offer **Retry account setup**,
which does not create another account. Email verification is no longer a navigation
gate; existing cloud rules still require it for shared data access. The dashboard
offers resend and verification refresh actions. Existing accounts and weak passwords display the Firebase error; no
fallback account is created. No passwords are stored in the database.

Deploy the updated profile rules before registration testing:
`firebase deploy --project YOUR_PROJECT_ID --only database`.
Enable **Email/Password** in Firebase Authentication, generate your ignored build
config with `scripts/Build-Config.ps1`, and launch with
`flutter run --dart-define-from-file=config/firebase.local.json`.
Without Firebase configuration, Register displays setup instructions and remains
on the form. Existing legacy profiles remain readable; new profiles contain no
role/category field.

`.env`, generated `config/firebase.local.json`, device `secrets.h`, native Firebase configuration files, service-account JSON, caches and build outputs are ignored by Git. Only placeholders are committed. The PowerShell script parses values as data, does not execute `.env` contents, rejects missing required values, and does not print them. Process environment values override `.env` for CI. Never add `.env` to Flutter assets. Build a separate configuration for each Firebase app/platform; iOS also needs `FIREBASE_IOS_BUNDLE_ID`.

**Environment injection keeps configuration out of source control; it cannot make Firebase client identifiers secret inside a shipped APK, IPA or web bundle.** Firebase API keys identify your project and are extractable from client applications. Authorization comes from Authentication and Security Rules. Never include service-account private keys, database legacy secrets, device passwords or Admin SDK credentials in the Flutter build. If your policy requires the Firebase configuration itself never to reach clients, use a separately authenticated server API instead of the direct Firebase client SDK architecture in this repository.

Official references: [Firebase API keys](https://firebase.google.com/docs/projects/api-keys), [security checklist](https://firebase.google.com/support/guides/security-checklist), and [custom claims](https://firebase.google.com/docs/auth/admin/custom-claims).

Before connecting devices:

1. Enable Email/Password sign-in. Set an appropriate Firebase password policy and email templates; authorize your web application's domain if using web.
2. Create RTDB and Storage in your selected region. Put their exact URLs/bucket names in `.env`. Restrict Firebase API keys to required APIs and supported application restrictions; use separate appropriately restricted client and device keys where needed.
3. Review and deploy the included rules to your own project:

   ```powershell
   firebase deploy --project YOUR_PROJECT_ID --only database,storage
   ```

4. Register a human user and verify their email. All verified human accounts share read access to the monitoring project. This is a **single shared monitoring workspace**, not private per-vendor tenancy. Account creation should be controlled if inspection data must not be readable by any self-registered verified user. Add organization membership rules before using this with multiple private organizations.
5. Approve inspector access with the trusted admin script. Only use this on a protected administrator workstation/server:

   ```powershell
   npm.cmd ci --prefix tools
   $env:GOOGLE_CLOUD_PROJECT = 'YOUR_PROJECT_ID'
   # Prefer Application Default Credentials/workload identity. If a JSON key is needed,
   # keep it outside the repository and restrict its filesystem access.
   $env:GOOGLE_APPLICATION_CREDENTIALS = 'C:\private\service-account.json'
   npm.cmd --prefix tools run role -- USER_UID inspector
   ```

   The administrator must have Firebase Auth administration permission. The app's top-right Refresh button refreshes subscriptions and custom claims. Available claim roles are `inspector`, `vendor`, `consumer`, `ph_device`, and `admin`. Registration never assigns claims. Unclaimed verified users have read access only. There is no administrator password in the app.
6. Create a separate Auth account for each pH device. Grant its UID `ph_device` using the same script, then place its dedicated credentials only in that board's local `secrets.h`. The device cannot read shared cloud records, modify history, publish as another device, or write image analyses. Disable/revoke the account if the board is lost. Protect production device flash using secure boot/flash encryption where supported.

App Check is an additional deployment hardening option. Direct ESP32 REST clients do not obtain an App Check token in this implementation. Do not blindly enforce it on RTDB and break device ingestion; use a trusted device ingestion gateway/custom attestation design before enabling enforcement there. Set Firebase quotas/budget alerts and define retention/backups for your deployment.

### Google sign-in

The Google button always uses real Firebase authentication. Enable Google in Firebase Authentication → Sign-in providers, set a support email, and authorize the web app domain. Web uses Firebase's popup provider directly. Native Android/iOS uses `google_sign_in` 7.2.0 and exchanges the Google ID token for a Firebase credential. See [Firebase's Flutter provider guide](https://firebase.google.com/docs/auth/flutter/federated-auth) and the [official plugin setup](https://pub.dev/packages/google_sign_in).

For Android without `google-services.json`, register your package name and SHA-1/SHA-256 signing fingerprints in the Firebase/Google project and set `GOOGLE_SERVER_CLIENT_ID` in `.env` to the project's **web OAuth client ID**. Leave `GOOGLE_CLIENT_ID` blank for Android. For iOS, set `GOOGLE_CLIENT_ID` to the iOS OAuth client ID, set `FIREBASE_IOS_BUNDLE_ID` to the actual bundle identifier, and add the reversed iOS client ID as a URL scheme in the Runner target per the plugin's iOS setup. Keep any local OAuth/native configuration out of source control. Run `scripts/Build-Config.ps1` again and rebuild after changes. These optional Google fields are not required for email authentication. Without a configured provider/registered native application, the Google callback reports an actionable error and you remain signed out; it never claims authentication succeeded.

## Data contract

| Path | Content | Access |
| --- | --- | --- |
| `/users/{uid}` | displayName, email, createdAt | Owner creates once and reads; no authorization claims stored here |
| `/telemetry/{deviceUid}` | Latest validated pH reading | Device writes only its own UID; verified humans read |
| `/readings/{recordId}` | Immutable pH inspection | Device appends; verified humans read |
| `/analyses/{recordId}` | sampleId, HSV metrics, result, storagePath, createdBy, timestamp | Approved inspector appends; verified humans read |
| `samples/{sampleId}/images/{filename}` in Storage | Private authenticated JPEG | Inspector creates with owner metadata; owner may clean up; verified humans read |

A pH reading has exactly `deviceId` (Auth UID), `ph` (0–14), `adcRaw` (averaged raw samples, strictly between 0 and 4095), `measuredVoltage` (0–3.3 V), and `timestamp` (Firebase server timestamp). Firmware atomically updates live telemetry and appends history. Rules enforce field types/ranges, device attribution, server timestamps and immutable logs. The obsolete publicly writable `/FishSamples` path is denied.

Image records also store normalized `meanSaturation`, `meanValue`, `redFraction`, and `usableFraction`, plus `meanHue` in degrees. The app stores authenticated Storage paths, never public download-token URLs. Upload failure leaves no successful analysis record. If the metadata write fails, the app attempts to delete the image and reports a cleanup failure; reconcile any orphaned Storage objects operationally. Storage content-type rules do not inspect image bytes; the app decodes and re-encodes snapshots to JPEG before upload.

Existing research screens, local persistence/report helpers and their tests remain in the repository for reference; they are not routes in the rewritten application's four-tab shell. Historical sample/device-upload schemas from that earlier prototype are not automatically migrated. Back up existing cloud data and migrate it deliberately to the contract above. Earlier `researcher`/`viewer` claims should be reviewed and replaced with the role policy above; no old client write permission is retained.

## ESP32 DevKit V1 wiring and calibration

Use a conditioned analog pH interface board; do not attach a bare electrode directly to GPIO34. Follow the supply requirements for your exact sensor-board revision. GPIO34 is ADC1 and input-only, so it works alongside Wi-Fi.

| Connection | ESP32 DevKit V1 |
| --- | --- |
| Sensor interface analog output | GPIO34, through conditioning/divider if required |
| Sensor interface ground | Common GND |
| Sensor interface power | Supply required by the exact board revision |
| Green LED anode through 220–330 Ω resistor | GPIO27 |
| Yellow LED anode through 220–330 Ω resistor | GPIO25 |
| Red LED anode through 220–330 Ω resistor | GPIO26 |
| All LED cathodes | GND |

Measure the analog output before connecting it. Never exceed the ESP32 input voltage limits. A module powered at 5 V may require voltage conditioning. The requested nominal calculation is `Vnominal = ADCraw × 3.3 / 4095`; this is an idealized scale, not the ESP32's physical internal reference. Firmware sets 12-bit ADC and 11 dB attenuation and separately averages `analogReadMilliVolts()` for the measured voltage used for pH calibration. Actual ADC range/nonlinearity depends on attenuation and chip calibration; avoid the rails and verify against a meter. See [Espressif ADC documentation](https://docs.espressif.com/projects/arduino-esp32/en/latest/api/adc.html).

The app and firmware use these exact boundaries:

| pH | Result | Physical LED |
| --- | --- | --- |
| `< 6.5` | Fresh | Green GPIO27 |
| `6.5 ≤ pH < 7.2` | Moderate | Yellow GPIO25 |
| `≥ 7.2` | Spoiled | Red GPIO26 |

Missing calibration, ADC clipping or pH outside 0–14 turns all physical LEDs off and suppresses publication. A disconnected device leaves its last record in Firebase; the app then shows STALE and gray indicators. Physical LEDs continue local classification while Wi-Fi is unavailable. Network work runs in a separate task so TLS requests do not stall ADC sampling. The single-slot outbound queue retains the latest pending reading, not a durable offline history; readings during outages can be lost. Do not assume gap-free audit logging.

Calibration:

1. Copy `firmware/esp32_ph_sensor/secrets.example.h` to `firmware/esp32_ph_sensor/secrets.h`.
2. Fill Wi-Fi, exact HTTPS database URL and the dedicated device's Auth credentials. Include trusted public PEM root CA certificates for both `identitytoolkit.googleapis.com` and your database hostname in `FIREBASE_ROOT_CA`. A concatenated PEM bundle is accepted; never paste private keys here. Select roots from the corresponding certificate issuers and maintain their expiry/rotation. TLS verification is mandatory; there is no `setInsecure()` fallback. Working DNS and NTP are required for TLS.
3. Leave `PH_CALIBRATION_CONFIRMED false`. Observe the measured voltage in serial at 115200 baud using certified pH 4 and pH 7 buffers, allowing the sensor to stabilize and following the sensor manufacturer's cleaning/temperature procedure.
4. Compute `slope = (7 − 4)/(V7 − V4)` and `offset = 7 − slope × V7`. Reject identical/unstable buffer voltages. Enter measured coefficients and set `PH_CALIBRATION_CONFIRMED true` only after validating against another buffer.
5. Flash and confirm physical LEDs and app results at the threshold boundaries. Firmware obtains a short-lived Firebase ID token over verified HTTPS, reauthenticates after 50 minutes, backs off failed sign-ins, and never logs passwords or tokens.

## ESP32-CAM streaming and controls

The camera sketch targets **AI Thinker ESP32-CAM / OV2640**, using the pin mapping in `firmware/esp32_cam/camera_pins.h`. This is a separate board from the pH device: its GPIO25/26/27/34 pins are already used by the camera and must not be wired as the pH board's LEDs/sensor.

Use a stable, adequately rated 5 V supply for the ESP32-CAM. Use 3.3 V UART logic when flashing, common ground, and GPIO0 to GND only during download mode; remove that strap before normal boot. The built-in flash is GPIO4. Do not use a microSD card concurrently with that flash pin configuration.

Copy `firmware/esp32_cam/secrets.example.h` to its local `secrets.h`. Set Wi-Fi, a strong unique camera password (at least 16 characters), and the exact browser app origin for CORS. No Firebase credentials are needed on the camera: the signed-in Flutter inspector uploads captured images.

| Endpoint | Purpose |
| --- | --- |
| `http://<camera-ip>/stream` | MJPEG video, port 80 |
| `http://<camera-ip>:81/capture` | JPEG snapshot |
| `http://<camera-ip>:81/control?var=framesize&val=8` | VGA; values 5=QVGA, 8=VGA, 9=SVGA |
| `http://<camera-ip>:81/control?var=flash&val=1` | Flash on; 0=off |

All endpoints require HTTP Basic authentication with username `camera` and the configured password. The app sends the authorization header, never credentials in the URL, and holds the password in memory only. Separate HTTP servers keep controls responsive during streaming; the camera mutex serializes sensor/capture access. Treat this as a single-viewer camera. Flash automatically turns off after 30 seconds to limit heat/current; the app switch also resets after 30 seconds. mDNS advertises `esp32cam.local` where supported.

In the app, enter the two base URLs (`http://192.168.1.50` and `http://192.168.1.50:81`, for example), enter the password, then Connect stream. Streaming stops on tab changes or when the app leaves the foreground. Reconnect explicitly after a disconnect. Snapshot capture displays the image and runs HSV analysis; gallery import is also supported. Approved inspectors can enter a sample ID and save the inspection to Firebase.

HTTP Basic authentication does **not** encrypt the LAN traffic. Use an isolated trusted Wi-Fi network, never forward these ports to the internet, and use a TLS gateway/VPN for remote access. The app rejects public HTTP camera hosts; HTTPS gateways are supported. Android cleartext is enabled for this LAN camera use; Firebase stays HTTPS. iOS declares local networking and its usage purpose; use `esp32cam.local` where numeric-IP ATS restrictions apply. Test permissions/transport on each target iOS version.

For Flutter web, run on a fixed local origin matching `CAMERA_ALLOWED_ORIGIN`, for example:

```powershell
flutter run -d chrome --web-port 5000 --dart-define-from-file=config/firebase.local.json
```

Browsers can block HTTP LAN cameras from HTTPS pages through mixed-content/private-network policies even with CORS. Use the native mobile build or a same-origin HTTPS camera gateway for a hosted web deployment. Do not disable browser security. The MJPEG client parses split JPEG markers, caps buffered frames at 2 MiB, limits render updates, times out stalled streams and closes connections on disposal.

## HSV method and limitations

The code analyzes the central 200 × 200 ROI after applying image orientation, on a worker isolate where supported. It computes circular mean hue, mean saturation/value and the fraction of usable pixels in the red hue sectors `[0°,20°] ∪ [340°,360°]`. It excludes saturation below 0.2, value below 0.15 and near-white glare; fewer than 20% usable pixels or a highly ambiguous circular mean requires recapture. Inputs are size-limited and decoded/re-encoded to JPEG before storage.

The initial heuristic labels red fraction ≥0.6 Fresh, ≥0.3 Moderate, otherwise Spoiled. These are explicitly **experimental defaults**, since no calibrated dataset or validated HSV classifier was supplied. Center only the gills in the ROI and control exposure, lighting, white balance and fish species. pH and HSV estimates remain separate. Neither proves food safety, and these thresholds need empirical validation before operational acceptance decisions.

## Build and verify

```powershell
dart format lib test
flutter analyze
flutter test
flutter build web --release --dart-define-from-file=config/firebase.local.json
# Configure your Android application ID and production signing before store release:
flutter build appbundle --release --dart-define-from-file=config/firebase.local.json
```

Android release builds require process environment variables `ANDROID_APPLICATION_ID`, `ANDROID_KEYSTORE_PATH`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` and `ANDROID_KEY_PASSWORD`. Supply them through your protected local/CI environment; keystores are ignored. Release builds fail if these are missing and never fall back to a debug key. Set `ANDROID_APPLICATION_ID` for debug builds too when testing a Firebase app restricted to your registered package. The namespace remains `com.example.aqua_sense` to match the existing native activity. Configure iOS bundle ID, signing, associated Firebase app and target-device permissions before distribution.

Android uses Kotlin Gradle plugin 2.4.21 to match the Kotlin 2.4 metadata in the current Firebase Auth Android dependency. Gradle 8.14 and AGP 8.11.1 are within the [Kotlin plugin compatibility range](https://kotlinlang.org/docs/gradle-configure-project.html). D8/R8 is explicitly pinned to 9.1.29 using the [official R8 override mechanism](https://r8.googlesource.com/r8.git/) to support this metadata during release shrinking; see the [Android Kotlin/D8/R8 compatibility table](https://developer.android.com/build/kotlin-support).

Rules tests use only emulators and a demo project:

```powershell
npm.cmd ci --prefix tools
firebase emulators:exec --only database,storage --project demo-aquasense "npm.cmd --prefix tools test"
```

Tests cover anonymous/unverified access, profile escalation, forged devices, atomic live/history writes, history immutability, field validation, inspector-only analyses and Storage ownership/type access. Flutter tests cover splash/auth validation, responsive layouts, stale/empty/error telemetry, pH boundaries, bounded MJPEG parsing, HSV input quality and CSV formula neutralization, alongside retained research utility tests.

Firmware uses the Espressif Arduino core and ArduinoJson 7.3.1 for the pH board. After installing Arduino CLI:

```powershell
arduino-cli core update-index --additional-urls https://espressif.github.io/arduino-esp32/package_esp32_index.json
arduino-cli core install esp32:esp32@3.3.12 --additional-urls https://espressif.github.io/arduino-esp32/package_esp32_index.json
arduino-cli lib install ArduinoJson@7.3.1
arduino-cli compile --fqbn esp32:esp32:esp32doit-devkit-v1 firmware/esp32_ph_sensor
arduino-cli compile --fqbn esp32:esp32:esp32cam firmware/esp32_cam
# Upload separately, replacing COMx with the correct board port:
arduino-cli upload --fqbn esp32:esp32:esp32doit-devkit-v1 --port COMx firmware/esp32_ph_sensor
arduino-cli upload --fqbn esp32:esp32:esp32cam --port COMx firmware/esp32_cam
```

No live Firebase project is provisioned or deployed by this rewrite. Hardware calibration, real camera throughput, supply integrity, sensor drift, device credential rotation and target-platform distribution must be accepted against your actual devices and project before production rollout.

The current UI test suite includes end-to-end simulated workflows and responsive image renders. Run `flutter test` and `flutter analyze` after changes. Real Google OAuth, live Firebase credentials, real camera transport, gallery dialogs and physical GPIO behavior still require integration checks on your target platform; simulation tests do not claim to validate external services. The earlier hardware/backend rewrite additionally passed six Firebase database/Storage emulator tests and compiled both sketches with Espressif Arduino core 3.3.12 and ArduinoJson 7.3.1. No board was flashed.

The Android release Gradle task also generated a signed, shrunk AAB using a temporary validation key, which was then deleted. Flutter's final bundle verification reported a debug-symbol stripping failure because this machine lacks Android SDK Command-line Tools (`apkanalyzer`); this is an environment check still to resolve before distribution. In Android Studio, open SDK Manager → SDK Tools → install Android SDK Command-line Tools (latest), run `flutter doctor -v`, then rebuild with your production configuration/signing. Validation artifacts in `build/` contain placeholders and are not production packages.

## Source structure

Current UI update verification: **53 passing Flutter tests**, including immediate
UID handoff, stale session events and auth-stack clearing; clean static analysis,
successful release web compilation and Android debug APK compilation. Responsive
renders at 320, 768 and 1440 pixels were visually inspected. Google provider
setup and live-device checks remain deployment-specific.

```text
lib/main.dart                         startup and authentication gate
lib/screens/login_screen.dart         email/password login and password reset
lib/screens/register_screen.dart      live Firebase registration (four fields, no role selection)
lib/widgets/account_setup_notice.dart nonblocking profile/verification feedback
lib/services/auth_session_controller.dart immediate SDK session and stale-event protection
lib/widgets/auth_navigation.dart       UID handoff and authentication stack clearing
lib/screens/app_shell.dart            navigation and claims refresh
lib/screens/dashboard_screen.dart     live pH and GPIO indicators
lib/screens/camera_screen.dart        stream, controls, snapshot, HSV and save
lib/screens/history_screen.dart       cloud tables, filters and CSV
lib/screens/settings_screen.dart      live connection and contrast settings
lib/services/demo_session.dart        synthetic sensor/image fixtures for component tests only
lib/widgets/soft_ui.dart              reusable Soft UI surfaces and ocean backdrop
lib/widgets/auth_layout.dart          responsive auth form and desktop hero
lib/models/telemetry.dart              telemetry validation and pH policy
lib/services/monitoring_repository.dart bounded cloud history and live streams
lib/services/camera_service.dart       HTTP controls and MJPEG parser
lib/services/gill_analysis_service.dart HSV processing and image validation
lib/services/firebase_service.dart     injected Firebase configuration/auth/storage
lib/core/app_preferences.dart          display preferences without authentication state
lib/widgets/auth_feedback.dart         authentication error mapping and Snackbars
lib/services/registration_service.dart real Auth creation and retryable profile/verification setup
firmware/esp32_ph_sensor/              calibrated ADC, LEDs and authenticated TLS ingestion
firmware/esp32_cam/                    authenticated LAN MJPEG camera and controls
scripts/Build-Config.ps1               safe .env → ignored build configuration
tools/                                trusted claims administration and emulator tests
database.rules.json / storage.rules    cloud authorization and schema validation
```
