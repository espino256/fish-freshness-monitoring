# Results cards and real sensor pH

Updated 2026-11-23 (Asia/Manila).

## Findings

The Camera & AI Inspection screen had no telemetry-stream input. It therefore
could not display ESP32 pH alongside image results. The dashboard and history
also substituted hardcoded sensor/image records whenever their real streams were
empty. Those substitutions could make unavailable data look like received cloud
measurements; they have been removed, including from history exports/charts.

The supplied screenshot shows an unverified email notice. The existing database
rules require a signed-in, email-verified human account to read `/telemetry` and
`/readings`. The UI now explains that requirement; database permissions were not
relaxed. No live authenticated Firebase session or physical sensor was available
to verify this account's actual telemetry during automated checks.

## What changed

- Added shared white/teal cards with softer borders, shadows, larger readable
  values and clear icon headings. Verified outcome, experimental prediction,
  model identity, score distribution and ROI descriptors remain distinct.
- Model details and score distribution sit beside each other on wider screens
  and stack on phones or at enlarged text sizes. Raw Output 0/1/2 order, real
  model identity and unverified class mappings are preserved.
- Added a prominent **Sensor pH** card to both Dashboard and Camera & AI
  Inspection, using the same existing live telemetry stream. It shows the real
  received pH, device, timestamp, ADC, measured/nominal voltage and feed status.
- Added CONNECTING, LIVE, STALE, UNAVAILABLE, ACCESS REQUIRED and NO READING
  states. Missing/error/invalid values show **pH N/A**, never zero or a fallback
  reading. The existing 20-second staleness / five-second future-clock policy
  remains in use, with periodic UI updates.
- More than one device requires an explicit choice. If a chosen device stops
  appearing, the card does not silently switch to another sensor. It retains
  device selection while the user scrolls to image results.
- Sensor pH is independent of the image, selected anatomy and model. Receiving
  pH updates does not change experimental AI scores, ROI descriptors or verified
  freshness. It is not automatically associated with a photographed fish/session.
- Page content centers at a readable maximum width; metric cards wrap based on
  available width and text scale. Chart legends wrap, desktop sidebar navigation
  scrolls in short windows, and compact mobile navigation uses **Inspect** while
  keeping **Camera & AI Inspection** as the page title and tooltip.
- Existing Firebase/history write services, ESP32 commands, authentication,
  inference service, preprocessing, runtime adapters and all five models were
  preserved. No automatic measurement or experimental-result writes were added.

`Telemetry.hasValidSensorValues` mirrors the existing numeric record contract:
finite pH 0..14, ADC 1..4094, measured voltage 0..3.3 V, device ID and a positive
timestamp. These are data-format checks, not proof of calibration or freshness.
Existing firmware pH-band/LED research estimates remain separate from the always
Inconclusive verified image result. No class mappings or confidence cutoffs were
invented.

## How to see actual pH

1. Use **Verify** on the account notice, complete the email link and recheck
   verification in the app. Existing verification code refreshes the auth token
   and reconnects cloud subscriptions.
2. Connect the calibrated ESP32 pH device to the correct Wi-Fi/Firebase project.
   Follow the existing firmware calibration instructions; do not substitute
   guessed calibration coefficients or fabricate a reading from a photograph.
3. Use **Refresh sensor feed**. With one publishing sensor its received value
   appears automatically; with several sensors choose the intended device.
4. If the card says STALE, inspect device power/network and the displayed
   timestamp. If it says ACCESS REQUIRED or UNAVAILABLE, follow its explanation
   and check the existing account/database configuration.

The actual ESP32 data contract remains:

```text
/telemetry/{deviceUid}
  deviceId, ph, adcRaw, measuredVoltage, timestamp
/readings/{recordId}
  deviceId, ph, adcRaw, measuredVoltage, timestamp
```

No sensor pH can be computed from the image in this application. N/A is the
correct state until a valid real sensor record is available.

## Verification

- PASSED: `flutter analyze`, no issues.
- PASSED: `flutter test --reporter expanded`, **137 tests**, zero failures.
- PASSED: all four real TFLite models in headless Chrome, including repeatability,
  reference CPU score checks, identity and disposal. The ROI integration check
  also renders the new pH card with an explicitly simulated telemetry fixture
  and proves the verified image result stays Inconclusive. Five substantive
  execution checks passed; the runner includes teardown in its +6 count.
- PASSED: responsive app navigation at 320x568, 390x844, 768x1024, 1280x900,
  1920x1080, 844x390 and 1100x420, at normal and 1.8x text scale. Real-record
  chart fixtures with long device names were scrolled/tested at widths 320,
  360, 768 and 1280 with 1.8x text. Earlier inspection tests also cover 320,
  768 and 1280 with enlarged text and actual gallery/image controls.
- PASSED: sensor loading/error/invalid/empty/stale states, multiple-device
  selection, no fabricated dashboard/history records, blocked access without
  subscribing, and independent sensor/image updates.
- PASSED: desktop/phone visual renders inspected. They are explicitly labeled
  synthetic pixel/sensor and test-double score fixtures, not scientific model
  validation or actual physical sensor measurements.
- PASSED: before/after SHA-256 checks for all five model files. The inference,
  image preparation, runtime adapters and protected Firebase/write services
  retain their original bytes for this UI task.
- PASSED: `flutter build apk --release`, exit code 0; the updated APK is
  129,667,417 bytes (about 123.7 MiB). Android SDK signature verification passed
  and the certificate matches the existing release key. All five APK model
  entries match their before-edit source hashes.
- PENDING: original real-image/Keras parity fixtures; that optional Chrome check
  remains explicitly skipped.
- PENDING: physical Android/iOS, ESP32 pH, live Firebase and OAuth testing.
  Device discovery lists Windows, Chrome and Edge; no Android device was attached.
  Widget-size checks do not establish a pass on every physical device.
- PENDING: independent-fish scientific validation and per-export label provenance.
  Named experimental classifications remain disabled; verified freshness remains
  Inconclusive, regardless of either a model score or the sensor pH.

The new signed APK was rebuilt at the existing path after source verification:
`build/app/outputs/flutter-apk/app-release.apk`. Its signature and packaged models
were checked after completion. Earlier APK sizes/checks in the release-signing
guide describe the prior build, not this updated UI artifact.

APK SHA-256: `670556f4bfff54b9f6a95613b056967b2fb44abdebe3ffd7aa22f3a0e46d878e`.

Local check records: `build/qa/ui_ph_tests.txt`, `ui_ph_analyze.txt`,
`ui_ph_release_build.txt`, `ui_ph_devices.json` and `ui_ph_integrity.json`.
Visual QA renders: `results_ph_desktop.png`, `results_ph_phone_top.png`,
`results_ph_phone_results.png` and `results_ph_phone_metrics.png` in `build/qa/`.

## Exact files changed or added

Application:

- `lib/core/app_theme.dart`
- `lib/models/telemetry.dart`
- `lib/screens/app_shell.dart`
- `lib/screens/camera_screen.dart`
- `lib/screens/dashboard_screen.dart`
- `lib/screens/history_screen.dart`
- `lib/widgets/experimental_inspection_details.dart`
- `lib/widgets/fish_region_selector.dart`
- `lib/widgets/inspection_card.dart` (new)
- `lib/widgets/live_ph_card.dart` (new)

Tests:

- `test/app_shell_navigation_test.dart`
- `test/camera_visual_inspection_test.dart`
- `test/widget_test.dart`
- `test/live_ph_card_test.dart` (new)
- `test/responsive_monitoring_ui_test.dart` (new)
- `integration_test/support/ai_platform_checks.dart`

Documentation:

- `README.md`
- `docs/RESULTS_AND_SENSOR_PH_UI.md` (this report)

Pre-existing user changes, release signing files, Android build configuration,
model binaries and training artifacts were not overwritten by this UI task.
