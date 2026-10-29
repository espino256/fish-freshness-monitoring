#pragma once
#define WIFI_SSID "replace-me"
#define WIFI_PASSWORD "replace-me"
// At least 16 characters. HTTP Basic authentication is LAN-only; use TLS
// termination on a trusted gateway before access outside the isolated LAN.
#define CAMERA_PASSWORD "replace-with-32-random-characters"
// Web browser origin allowed by CORS; use your exact app origin, no wildcard.
#define CAMERA_ALLOWED_ORIGIN "http://localhost:5000"
