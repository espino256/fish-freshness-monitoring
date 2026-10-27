
#include <Arduino.h>
#include <WiFi.h>
#include <math.h>
#include "../secrets.h"

// ESP32 DevKit V1 pin configuration
constexpr int PH_PIN = 34;
constexpr int LED_GREEN = 27;
constexpr int LED_YELLOW = 25;
constexpr int LED_RED = 26;

constexpr unsigned long SAMPLE_INTERVAL = 20;
constexpr unsigned long DISPLAY_INTERVAL = 800;
constexpr unsigned long WIFI_TIMEOUT = 15000;
constexpr int SAMPLE_COUNT = 10;

// Set these in secrets.h after two-point calibration.
// PH_CALIBRATION_CONFIRMED = true
// PH_SLOPE = calibrated slope
// PH_OFFSET = calibrated offset

#ifndef PH_CALIBRATION_CONFIRMED
#define PH_CALIBRATION_CONFIRMED false
#endif

#ifndef PH_SLOPE
#define PH_SLOPE 0.0f
#endif

#ifndef PH_OFFSET
#define PH_OFFSET 0.0f
#endif

uint32_t phSamples[SAMPLE_COUNT] = {};
int sampleIndex = 0;
int samplesCollected = 0;

unsigned long lastSample = 0;
unsigned long lastDisplay = 0;

enum FreshnessStatus {
  FRESH,
  MODERATE,
  SPOILED,
  INVALID
};

void setLEDs(bool green, bool yellow, bool red) {
  digitalWrite(LED_GREEN, green ? HIGH : LOW);
  digitalWrite(LED_YELLOW, yellow ? HIGH : LOW);
  digitalWrite(LED_RED, red ? HIGH : LOW);
}

void showStatus(FreshnessStatus status) {
  switch (status) {
    case FRESH:
      setLEDs(true, false, false);
      Serial.println("Status: FRESH");
      break;

    case MODERATE:
      setLEDs(false, true, false);
      Serial.println("Status: MODERATE");
      break;

    case SPOILED:
      setLEDs(false, false, true);
      Serial.println("Status: SPOILED");
      break;

    default:
      setLEDs(false, false, false);
      Serial.println("Status: NOT CALIBRATED / INVALID");
      break;
  }
}

float getAverageVoltage() {
  uint32_t total = 0;

  for (int i = 0; i < samplesCollected; i++) {
    total += phSamples[i];
  }

  if (samplesCollected == 0) return NAN;

  return (total / (float)samplesCollected) / 1000.0f;
}

FreshnessStatus classifyPH(float ph) {
  if (!isfinite(ph) || ph < 0 || ph > 14) {
    return INVALID;
  }

  // Experimental project thresholds only
  if (ph >= 6.2f && ph < 6.5f) {
    return FRESH;
  }

  if (ph >= 6.5f && ph <= 7.0f) {
    return MODERATE;
  }

  if (ph > 7.0f) {
    return SPOILED;
  }

  // Values below 6.2 need review
  return INVALID;
}

void setup() {
  Serial.begin(115200);
  delay(1000);

  pinMode(LED_GREEN, OUTPUT);
  pinMode(LED_YELLOW, OUTPUT);
  pinMode(LED_RED, OUTPUT);

  // All LEDs ON during initialization
  setLEDs(true, true, true);
  Serial.println("AquaSense initializing...");

  analogReadResolution(12);
  analogSetPinAttenuation(PH_PIN, ADC_11db);

  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  Serial.println("Connecting to Wi-Fi...");

  unsigned long start = millis();

  while (WiFi.status() != WL_CONNECTED &&
         millis() - start < WIFI_TIMEOUT) {
    delay(500);
    Serial.print(".");
  }

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\nWi-Fi connected!");
    Serial.println(WiFi.localIP());
  } else {
    Serial.println("\nWi-Fi unavailable.");
    Serial.println("Continuing sensor monitoring offline.");
  }

  // Turn all LEDs OFF after initialization
  setLEDs(false, false, false);

  Serial.println("AquaSense pH monitoring ready.");
}

void loop() {
  unsigned long now = millis();

  if (now - lastSample >= SAMPLE_INTERVAL) {
    lastSample = now;

    phSamples[sampleIndex] =
        analogReadMilliVolts(PH_PIN);

    sampleIndex = (sampleIndex + 1) % SAMPLE_COUNT;

    if (samplesCollected < SAMPLE_COUNT) {
      samplesCollected++;
    }
  }

  if (now - lastDisplay >= DISPLAY_INTERVAL) {
    lastDisplay = now;

    float voltage = getAverageVoltage();

    Serial.printf("Voltage: %.3f V | ", voltage);

    if (!PH_CALIBRATION_CONFIRMED ||
        PH_SLOPE == 0.0f) {
      showStatus(INVALID);
      return;
    }

    float ph = PH_SLOPE * voltage + PH_OFFSET;

    Serial.printf("pH: %.2f | ", ph);

    FreshnessStatus status = classifyPH(ph);
    showStatus(status);
  }
}
