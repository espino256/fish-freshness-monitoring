# AquaSense audit report

Baseline inspected on 2026-11-13.

| Severity | Finding | Correction |
|---|---|---|
| High | `camera_screen.dart` classified an assumed centre area using HSV values. | Active flow now requires manual part selection and returns Inconclusive without a verified model. |
| High | `ph_measurement_history_service.dart` wrote legacy `FishSamples`, which the supplied rules deny and ESP32 firmware does not use. | Confirmed records use immutable `/measurement_history`; ESP32 remains sole owner of `/telemetry` and `/readings`. |
| High | Android release fell back to debug signing. | Release builds now fail unless all signing environment variables are supplied. |
| Medium | Duplicate self/Flutter imports caused analyzer warnings. | Removed. |
| Medium | Bundled TFLite model has no label map or validation metadata. | Preserved but not invoked. |
| Blocker | `firmware/esp32_cam/camerawebserver.ino` contains literal Wi-Fi credentials. | Do not flash or commit it; use the secured `esp32_cam.ino` plus `secrets.example.h` pattern. |
