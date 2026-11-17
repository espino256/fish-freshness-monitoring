# Firebase schema

`/telemetry/{deviceUid}` and `/readings/{id}` are ESP32 records with `deviceId`, `ph`, `adcRaw`, `measuredVoltage`, and server `timestamp`. `/measurement_history/{id}` is an inspector-created immutable record with `measurementId`, `fishOrSessionId`, `ph`, `status`, `source`, and server `timestamp`. The legacy `/FishSamples` tree is intentionally not writable under the supplied rules.
