# AquaSense

A responsive Flutter research workspace for fish-freshness observations. The
current workspace contained no capstone document or existing application, so
the initial thresholds and hardware assumptions below come from the supplied
project brief. No pH values or freshness results are simulated.

The hero and gill-panel visuals in `assets/images/` are original local SVG
illustrations created for this app. They are not photographs or research
evidence. No third-party image assets are used.

## Run locally

Requirements: Flutter stable (Dart 3.10+).

```powershell
flutter pub get
flutter run -d chrome
```

Without Firebase values, the app opens in **Local workspace mode**. Sample
metadata, thresholds, and manual calibration records are stored in local
preferences. Live readings, cloud history, image uploads, and sign-in are
unavailable until Firebase is configured. Local preference storage is not
encrypted; do not enter sensitive personal information.

The same source supports Android, iOS, web, and Windows. Image selection,
camera access, print/share, and plugin support vary by platform.

## Firebase setup

1. Create a Firebase project. Enable Email/Password Authentication, Realtime
   Database, and Storage.
2. Deploy the restrictive rules in `database.rules.json` and `storage.rules`
   using the Firebase CLI:

   ```powershell
   firebase deploy --only database,storage
   ```

3. Provision user accounts and assign **custom claims only from a trusted
   server environment** using the Firebase Admin SDK. Do not assign roles from
   this client app. Supported roles are:
   - `admin`: policy/configuration administration.
   - `researcher`: sample metadata, image analysis, and research reads.
   - `viewer`: read-only research access.
   - `ph_device`: append pH readings and update its own status.
   - `camera_device`: upload sample images and update its own status.

   Example server-side Admin SDK operation (run in a protected admin
   environment, never in the app or firmware):

   ```javascript
   await getAuth().setCustomUserClaims(uid, { role: "researcher" });
   ```

   Users need to refresh their authentication token after a claim change.
   Create one restricted account per device; do not use an administrator
   account on hardware.
4. Configure Flutter with the Firebase public app identifiers. These are
   project configuration, not service-account secrets. Restrict API keys by
   application/platform and enable only required Firebase APIs.

   ```powershell
   flutter run -d chrome `
     --dart-define=FIREBASE_API_KEY=YOUR_WEB_API_KEY `
     --dart-define=FIREBASE_APP_ID=YOUR_WEB_APP_ID `
     --dart-define=FIREBASE_MESSAGING_SENDER_ID=YOUR_SENDER_ID `
     --dart-define=FIREBASE_PROJECT_ID=YOUR_PROJECT_ID `
     --dart-define=FIREBASE_DATABASE_URL=https://YOUR_PROJECT-default-rtdb.firebaseio.com `
     --dart-define=FIREBASE_STORAGE_BUCKET=YOUR_PROJECT.firebasestorage.app
   ```

   Supply the platform-specific Firebase app values when building for a
   different platform. The app intentionally does not include generated
   Firebase options, credentials, or service-account keys.
5. Sign in with a provisioned researcher account. A user who is not signed in
   can continue to use local sample metadata, but cloud sync is not claimed.
   With Firebase configured, AquaSense starts at its branded sign-in screen
   when signed out and routes authenticated users into the monitoring
   workspace. Account creation remains administrator-managed; public
   registration is intentionally not provided.

### Data layout

- `/users/{uid}` — profile metadata; privileged role claims are managed
  server-side, not by the client.
- `/samples/{sampleId}` — owner-bound sample metadata.
- `/readings/{pushId}` — immutable device readings (`ph`, server timestamp,
  device UID, optional sample ID).
- `/analyses/{pushId}` — mean hue, classification, sample ID, timestamp,
  creator, and controlled Storage path.
- `/deviceUploads/{pushId}` — raw images uploaded by the camera device.
- `/devices/{esp32-ph|esp32-cam}` — online flag and server-side heartbeat.
- `/calibrations/{id}` — reserved for authorized hardware calibration history.
- `/settings/classificationThresholds` — reserved for admin-managed shared
  thresholds. The current settings screen saves local overrides only.

Storage objects use `samples/{sampleId}/images/{fileName}`. The app stores the
Storage path, not a public download token, and downloads image bytes through
authenticated Firebase Storage access.

## Threshold behavior and limitations

The supplied project brief gives pH Fresh 6.2–6.5, Moderate 6.5–7.0, Spoiled
above 7.0, with hue Fresh 5–25, Moderate 25–45, and Spoiled below 5 or above
45. Boundaries are explicit and non-overlapping:

- pH `[6.2, 6.5)` Fresh; `[6.5, 7.0]` Moderate; `> 7.0` Spoiled; below 6.2
  requires review. Invalid/missing readings are not classified.
- Mean hue `[5, 25)` Fresh; `[25, 45]` Moderate; `< 5` or `> 45` Spoiled.
  Hue outside 0–360 is invalid.

The image workflow uses the centered 200 × 200 pixel region, an RGB-to-HSV Hue
conversion, and the circular mean of pixel hue values. Center the gill
cover in the source image before analysis. Lighting, camera white balance,
sample preparation, and ROI placement can change the result. These are initial
research parameters, not validated universal freshness or food-safety
criteria. pH and image results remain separate; conflicts are flagged, never
combined into an unvalidated score.

## Device firmware

Source sketches:

- `firmware/esp32_ph_sensor/esp32_ph_sensor.ino`
- `firmware/esp32_cam/esp32_cam.ino`

Install the ESP32 board support, the `Firebase ESP Client` Arduino library,
and (for the camera) the ESP32 camera/SPIFFS support. Copy
`firmware/secrets.example.h` to `firmware/secrets.h`, fill in Wi-Fi and
device-specific Firebase credentials, and keep that file private. Assign
`ph_device` or `camera_device` custom claims to the corresponding Firebase
device account. The pH sketch samples GPIO34 every five seconds, averages ADC
voltage samples, and does **not** publish pH until calibration is confirmed.

For the DFRobot SEN0161-V2, connect sensor-board analog output to ESP32 GPIO34
(ADC1 input), ground to common ground, and power according to the exact
board revision. Verify output voltage never exceeds the ESP32 ADC input limit;
use a suitable divider/conditioning circuit if needed. Calibrate with pH 4 and
pH 7 buffers, then enter the measured linear slope and offset in the firmware
and explicitly set `PH_CALIBRATION_CONFIRMED` true. Do not assume the
application's manual calibration entry changes hardware coefficients.

The ESP32-CAM sketch targets an AI Thinker ESP32-CAM with OV2640. It captures
VGA 640 × 480 JPEG frames on a debounced GPIO13 button press or serial `c`
command, uploads to Storage, and records a Storage path in `/deviceUploads`.
Wi-Fi and camera initialization retry without blocking indefinitely; temporary
images are written to SPIFFS. The dedicated temporary-image filesystem may be
formatted on its first mount if it is unformatted; subsequent retries do not
format it again. Do not store other persistent data in that SPIFFS partition.
Sample IDs are restricted to 1–100 ASCII letters, digits, hyphens, or
underscores, and the JPEG must be smaller than 10 MiB. If the Storage upload
succeeds but the Realtime Database metadata write fails, the sketch logs the
orphaned Storage path for authorized cleanup; the firmware does not silently
claim the capture succeeded. The sketch does not claim
to calculate hue. Signed-in users with an authorized Firebase role can browse
the latest 20 device uploads in Visual Analysis, load an image through
authenticated Storage access, and analyze it locally. Saving the result creates
an analysis record that references the original camera image; it does not
upload a duplicate. The associated sample must be available in the workspace.

Basic wiring/setup:

- **pH board:** SEN0161-V2 `Analog Out` → ESP32 `GPIO34`; `GND` → `GND`;
  supply per board revision, with a shared ground.
- **ESP32-CAM:** use the AI Thinker board pinout and a stable 5 V supply sized
  for camera/Wi-Fi current peaks. The sketch uses GPIO13 as a button to GND.
  For serial flashing, use a 3.3 V UART adapter, connect GPIO0 to GND only
  while entering download mode, then remove that strap before normal use.

Hardware, wiring, Firebase project rules, and firmware behavior have not been
tested against physical devices in this workspace. The ESP32-CAM sketch has
not been compiled here because Arduino CLI/PlatformIO and the Firebase ESP
Client library are not installed.

## Implementation notes

- `lib/models/` contains sample, device, reading, and classification models.
- `lib/services/` contains Firebase access, local persistence, image
  processing, and report generation.
- `lib/screens/` contains responsive feature screens and navigation.
- `lib/widgets/` contains responsive ocean-tech surfaces, brand/loading
  components, and local illustrations.
- `test/` covers classification boundaries, invalid input, ROI processing,
  report generation, and mobile/wide dashboard rendering.

The visual-analysis screen processes the selected image locally first. Saving
an analysis is an explicit action and requires an authenticated researcher. The
PDF/CSV report includes available local sample/calibration records and current
cloud readings/analyses; unavailable data is omitted, not invented.
PDFs embed the Roboto regular and bold fonts from the Flutter SDK; the font
license is included at `assets/fonts/Roboto-LICENSE.txt`. When signed out,
reports explicitly include local sample and calibration records only.

## Validation

```powershell
dart format lib test
flutter analyze
flutter test
```

No credentials, Firebase project, ESP32 boards, sensor, or camera were
provided. Therefore Firebase authorization rules require validation with the
Firebase Emulator Suite, and firmware requires Arduino compilation and
physical-device testing before research use.
