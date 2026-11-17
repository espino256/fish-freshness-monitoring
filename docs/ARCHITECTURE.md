# Architecture

ESP32 pH firmware atomically writes current `/telemetry/{deviceUid}` and append-only `/readings/{id}`. Flutter reads those through `MonitoringRepository`. A human-confirmed association is separately saved to immutable `/measurement_history/{id}`; it never changes live telemetry. Camera input is manually identified as gills, eyes, or skin/scales, quality screened, then marked Inconclusive until a validated per-part model is supplied.
