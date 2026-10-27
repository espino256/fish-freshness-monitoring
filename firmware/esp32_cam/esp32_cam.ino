
#include <Arduino.h>
#include "esp_camera.h"
#include <WiFi.h>
#include <WebServer.h>
#include "../secrets.h"

// AI Thinker ESP32-CAM OV2640 pins
#define PWDN_GPIO_NUM 32
#define RESET_GPIO_NUM -1
#define XCLK_GPIO_NUM 0
#define SIOD_GPIO_NUM 26
#define SIOC_GPIO_NUM 27
#define Y9_GPIO_NUM 35
#define Y8_GPIO_NUM 34
#define Y7_GPIO_NUM 39
#define Y6_GPIO_NUM 36
#define Y5_GPIO_NUM 21
#define Y4_GPIO_NUM 19
#define Y3_GPIO_NUM 18
#define Y2_GPIO_NUM 5
#define VSYNC_GPIO_NUM 25
#define HREF_GPIO_NUM 23
#define PCLK_GPIO_NUM 22

WebServer server(80);
bool cameraReady = false;

void handleRoot() {
  server.send(
    200,
    "text/html",
    "<html><head><meta name='viewport' "
    "content='width=device-width,initial-scale=1'>"
    "</head><body style='font-family:Arial;"
    "text-align:center;background:#eef8fc'>"
    "<h2>AquaSense ESP32-CAM</h2>"
    "<p>Fish Image Capture</p>"
    "<img src='/capture' style='max-width:95%;"
    "border-radius:12px'>"
    "<p><a href='/capture'>Capture Image</a></p>"
    "<p>Refresh page for a new image.</p>"
    "</body></html>"
  );
}

void handleCapture() {
  if (!cameraReady) {
    server.send(503, "text/plain", "Camera unavailable");
    return;
  }

  camera_fb_t* frame = esp_camera_fb_get();

  if (!frame) {
    server.send(500, "text/plain", "Capture failed");
    return;
  }

  WiFiClient client = server.client();

  server.setContentLength(frame->len);
  server.send(200, "image/jpeg", "");

  size_t sent = client.write(frame->buf, frame->len);

  if (sent != frame->len) {
    Serial.println("Incomplete image transfer.");
  }

  esp_camera_fb_return(frame);
}

bool initializeCamera() {
  camera_config_t config = {};

  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer = LEDC_TIMER_0;

  config.pin_d0 = Y2_GPIO_NUM;
  config.pin_d1 = Y3_GPIO_NUM;
  config.pin_d2 = Y4_GPIO_NUM;
  config.pin_d3 = Y5_GPIO_NUM;
  config.pin_d4 = Y6_GPIO_NUM;
  config.pin_d5 = Y7_GPIO_NUM;
  config.pin_d6 = Y8_GPIO_NUM;
  config.pin_d7 = Y9_GPIO_NUM;

  config.pin_xclk = XCLK_GPIO_NUM;
  config.pin_pclk = PCLK_GPIO_NUM;
  config.pin_vsync = VSYNC_GPIO_NUM;
  config.pin_href = HREF_GPIO_NUM;
  config.pin_sccb_sda = SIOD_GPIO_NUM;
  config.pin_sccb_scl = SIOC_GPIO_NUM;

  config.pin_pwdn = PWDN_GPIO_NUM;
  config.pin_reset = RESET_GPIO_NUM;

  config.xclk_freq_hz = 20000000;
  config.pixel_format = PIXFORMAT_JPEG;

  config.frame_size = FRAMESIZE_VGA;
  config.jpeg_quality = 12;
  config.fb_count = 1;

  config.fb_location = psramFound()
      ? CAMERA_FB_IN_PSRAM
      : CAMERA_FB_IN_DRAM;

  config.grab_mode = CAMERA_GRAB_WHEN_EMPTY;

  esp_err_t err = esp_camera_init(&config);

  if (err != ESP_OK) {
    Serial.printf(
      "Camera initialization failed: 0x%x\n",
      err
    );
    return false;
  }

  return true;
}

void setup() {
  Serial.begin(115200);
  delay(1000);

  Serial.println("Starting AquaSense ESP32-CAM...");

  cameraReady = initializeCamera();

  if (!cameraReady) {
    Serial.println("Camera initialization failed.");
    return;
  }

  Serial.println("Camera initialized.");

  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  Serial.print("Connecting to Wi-Fi");

  unsigned long start = millis();

  while (WiFi.status() != WL_CONNECTED &&
         millis() - start < 20000) {
    delay(500);
    Serial.print(".");
  }

  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("\nWi-Fi connection failed.");
    return;
  }

  Serial.println("\nWi-Fi connected!");

  server.on("/", HTTP_GET, handleRoot);
  server.on("/capture", HTTP_GET, handleCapture);
  server.begin();

  Serial.print("Camera URL: http://");
  Serial.println(WiFi.localIP());
}

void loop() {
  if (WiFi.status() == WL_CONNECTED) {
    server.handleClient();
  }

  delay(2);
}
