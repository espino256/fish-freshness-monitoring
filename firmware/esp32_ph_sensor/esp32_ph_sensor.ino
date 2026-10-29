#include <Arduino.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <time.h>
#include <math.h>
#include "secrets.h"

constexpr int PH_PIN = 34, GREEN = 27, YELLOW = 25, RED = 26;
constexpr uint32_t SAMPLE_MS = 20, PUBLISH_MS = 5000;
constexpr size_t SAMPLE_COUNT = 32;
uint16_t rawSamples[SAMPLE_COUNT] = {}, mvSamples[SAMPLE_COUNT] = {};
size_t cursor = 0, count = 0;
uint32_t lastSample = 0, lastPublish = 0, lastAuthAttempt = 0, signedInAt = 0;
uint32_t bootId = 0, sequence = 0;
String idToken, deviceUid;
struct OutboundReading { float ph, raw, measured; };
QueueHandle_t telemetryQueue = nullptr;

void leds(int state) {
  digitalWrite(GREEN, state == 0); digitalWrite(YELLOW, state == 1); digitalWrite(RED, state == 2);
}
int classification(float ph) {
  if (!isfinite(ph) || ph < 0 || ph > 14) return -1;
  return ph < 6.5f ? 0 : ph < 7.2f ? 1 : 2;
}
// TLS certificate chain and host verification are mandatory. SNTP sets the clock.
int request(const String &url, const String &method, const String &payload, String *response = nullptr) {
  WiFiClientSecure tls;
  tls.setCACert(FIREBASE_ROOT_CA);
  tls.setHandshakeTimeout(8);
  HTTPClient http;
  http.setConnectTimeout(5000); http.setTimeout(5000);
  if (!url.startsWith("https://") || !http.begin(tls, url)) return -1;
  http.addHeader("Content-Type", "application/json");
  int code = http.sendRequest(method.c_str(), payload);
  if (response && code == 200) *response = http.getString();
  http.end();
  return code;
}
bool authenticate() {
  const uint32_t now = millis();
  if (idToken.length() && now - signedInAt < 50UL * 60UL * 1000UL) return true;
  if (now - lastAuthAttempt < 30000) return false;
  lastAuthAttempt = now;
  if (WiFi.status() != WL_CONNECTED || time(nullptr) < 1700000000) return false;
  JsonDocument body;
  body["email"] = DEVICE_EMAIL; body["password"] = DEVICE_PASSWORD; body["returnSecureToken"] = true;
  String payload, response;
  serializeJson(body, payload);
  const int code = request(String("https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=") + FIREBASE_API_KEY, "POST", payload, &response);
  if (code != 200) { Serial.printf("Device authentication failed (%d).\n", code); return false; }
  JsonDocument result;
  if (deserializeJson(result, response) || !result["idToken"].is<String>() || !result["localId"].is<String>()) return false;
  idToken = result["idToken"].as<String>(); deviceUid = result["localId"].as<String>(); signedInAt = now;
  return true;
}
void publish(float ph, float raw, float measuredVoltage) {
  if (!authenticate()) return;
  JsonDocument update;
  // One atomic update keeps live telemetry and immutable history in sync.
  const String key = deviceUid + "_" + String(bootId, HEX) + "_" + String(sequence++);
  JsonObject live = update[String("telemetry/") + deviceUid].to<JsonObject>();
  live["deviceId"] = deviceUid; live["ph"] = ph; live["adcRaw"] = raw;
  live["measuredVoltage"] = measuredVoltage; live["timestamp"][".sv"] = "timestamp";
  update[String("readings/") + key] = live;
  String payload;
  serializeJson(update, payload);
  String base = FIREBASE_DATABASE_URL;
  while (base.endsWith("/")) base.remove(base.length() - 1);
  const int code = request(base + "/.json?auth=" + idToken, "PATCH", payload);
  if (code == 401 || code == 403) idToken = "";
  if (code != 200) Serial.printf("Telemetry not persisted (%d). No cloud success assumed.\n", code);
}
void networkWorker(void *) {
  OutboundReading reading;
  for (;;) {
    if (xQueueReceive(telemetryQueue, &reading, portMAX_DELAY) == pdTRUE && WiFi.status() == WL_CONNECTED) {
      publish(reading.ph, reading.raw, reading.measured);
    }
  }
}
void setup() {
  Serial.begin(115200);
  for (int pin : {GREEN, YELLOW, RED}) pinMode(pin, OUTPUT);
  leds(-1);
  analogReadResolution(12); analogSetPinAttenuation(PH_PIN, ADC_11db);
  bootId = esp_random();
  WiFi.mode(WIFI_STA); WiFi.setAutoReconnect(true); WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  configTime(0, 0, "pool.ntp.org", "time.google.com");
  telemetryQueue = xQueueCreate(1, sizeof(OutboundReading));
  if (!telemetryQueue || xTaskCreatePinnedToCore(networkWorker, "cloud", 12288, nullptr, 1, nullptr, 0) != pdPASS) {
    Serial.println("Cloud worker unavailable; local monitoring only.");
    telemetryQueue = nullptr;
  }
  Serial.println("AquaSense: GPIO34 ADC; LEDs GPIO27/25/26. Calibration required.");
}
void loop() {
  const uint32_t now = millis();
  if (now - lastSample >= SAMPLE_MS) {
    lastSample = now;
    rawSamples[cursor] = analogRead(PH_PIN);
    mvSamples[cursor] = analogReadMilliVolts(PH_PIN);
    cursor = (cursor + 1) % SAMPLE_COUNT;
    if (count < SAMPLE_COUNT) count++;
  }
  if (now - lastPublish >= PUBLISH_MS) {
    lastPublish = now;
    if (count < SAMPLE_COUNT) { leds(-1); return; }
    uint32_t rawTotal = 0, mvTotal = 0;
    bool rail = false;
    for (size_t i = 0; i < count; i++) {
      rawTotal += rawSamples[i]; mvTotal += mvSamples[i];
      if (rawSamples[i] == 0 || rawSamples[i] == 4095) rail = true;
    }
    const float raw = rawTotal / float(count), measured = mvTotal / (1000.0f * count);
    if (!PH_CALIBRATION_CONFIRMED || !isfinite(PH_SLOPE) || PH_SLOPE == 0 || !isfinite(PH_OFFSET) || rail || measured > 3.3f) {
      leds(-1); Serial.printf("Uncalibrated/invalid: measured %.4f V, nominal %.4f V\n", measured, raw * 3.3f / 4095.0f); return;
    }
    const float ph = PH_SLOPE * measured + PH_OFFSET;
    const int state = classification(ph);
    leds(state);
    if (state < 0) { Serial.println("Invalid pH; not published."); return; }
    Serial.printf("pH %.3f, measured %.4f V, nominal %.4f V\n", ph, measured, raw * 3.3f / 4095.0f);
    if (telemetryQueue) {
      OutboundReading reading{ph, raw, measured};
      xQueueOverwrite(telemetryQueue, &reading);
    }
  }
  delay(1);
}
