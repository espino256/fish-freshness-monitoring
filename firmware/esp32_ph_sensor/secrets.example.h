#pragma once
#define WIFI_SSID "TP-Link_Guest_Mode"
#define WIFI_PASSWORD "!@#$%^&*()"
#define FIREBASE_API_KEY "AIzaSyDYBLVJPQwpU1k8ko_5lviqqlZ_QYgUue0"
#define FIREBASE_DATABASE_URL "https://replace-me-default-rtdb.firebaseio.com"
// Dedicated Firebase Authentication account with custom role ph_device.
#define DEVICE_EMAIL "marylyntamagos@gmail.com"
#define DEVICE_PASSWORD "123456789"
// Public CA certificates, NOT private keys. Include roots for identitytoolkit.googleapis.com
// and your RTDB hostname. Keep certificates updated. No insecure TLS fallback exists.
static const char FIREBASE_ROOT_CA[] = R"PEM(-----BEGIN CERTIFICATE-----
REPLACE_WITH_TRUSTED_ROOT_CA_PEM
-----END CERTIFICATE-----
)PEM";
// Measure voltage in certified pH 4 and pH 7 buffers before enabling publication.
// slope = (7 - 4)/(V7 - V4); offset = 7 - slope * V7.
#define PH_CALIBRATION_CONFIRMED false
#define PH_SLOPE 0.0f
#define PH_OFFSET 0.0f
