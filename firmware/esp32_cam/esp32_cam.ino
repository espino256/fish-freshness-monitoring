#include <Arduino.h>
#include <WiFi.h>
#include <ESPmDNS.h>
#include "esp_camera.h"
#include "esp_http_server.h"
#include "mbedtls/base64.h"
#include "camera_pins.h"
#include "secrets.h"

httpd_handle_t streamServer = nullptr, controlServer = nullptr;
SemaphoreHandle_t cameraMutex;
String expectedAuth;
volatile uint32_t flashEnabledAt = 0;
volatile bool flashEnabled = false;

void cors(httpd_req_t *req) {
  httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", CAMERA_ALLOWED_ORIGIN);
  httpd_resp_set_hdr(req, "Access-Control-Allow-Headers", "Authorization, Content-Type");
  httpd_resp_set_hdr(req, "Access-Control-Allow-Methods", "GET, OPTIONS");
  httpd_resp_set_hdr(req, "Cache-Control", "no-store");
}
bool authorized(httpd_req_t *req) {
  cors(req);
  const size_t length = httpd_req_get_hdr_value_len(req, "Authorization");
  char value[256];
  if (length >= sizeof(value) || httpd_req_get_hdr_value_str(req, "Authorization", value, sizeof(value)) != ESP_OK || expectedAuth != value) {
    httpd_resp_set_status(req, "401 Unauthorized");
    httpd_resp_set_hdr(req, "WWW-Authenticate", "Basic realm=\"AquaSense\"");
    httpd_resp_send(req, "Unauthorized", HTTPD_RESP_USE_STRLEN);
    return false;
  }
  return true;
}
esp_err_t optionsHandler(httpd_req_t *req) { cors(req); return httpd_resp_send(req, nullptr, 0); }
esp_err_t busy(httpd_req_t *req) {
  httpd_resp_set_status(req, "503 Service Unavailable");
  return httpd_resp_send(req, "Camera busy", HTTPD_RESP_USE_STRLEN);
}

esp_err_t captureHandler(httpd_req_t *req) {
  if (!authorized(req)) return ESP_OK;
  if (xSemaphoreTake(cameraMutex, pdMS_TO_TICKS(3000)) != pdTRUE) return busy(req);
  camera_fb_t *frame = esp_camera_fb_get();
  if (!frame) { xSemaphoreGive(cameraMutex); return httpd_resp_send_err(req, HTTPD_500_INTERNAL_SERVER_ERROR, "Capture failed"); }
  httpd_resp_set_type(req, "image/jpeg");
  esp_err_t result = httpd_resp_send(req, reinterpret_cast<const char *>(frame->buf), frame->len);
  esp_camera_fb_return(frame); xSemaphoreGive(cameraMutex);
  return result;
}
esp_err_t controlHandler(httpd_req_t *req) {
  if (!authorized(req)) return ESP_OK;
  char query[96], name[20], value[12];
  if (httpd_req_get_url_query_str(req, query, sizeof(query)) != ESP_OK || httpd_query_key_value(query, "var", name, sizeof(name)) != ESP_OK || httpd_query_key_value(query, "val", value, sizeof(value)) != ESP_OK) return httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "Missing control");
  char *end;
  long selected = strtol(value, &end, 10);
  if (*end || end == value) return httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "Invalid value");
  if (!strcmp(name, "flash") && (selected == 0 || selected == 1)) {
    flashEnabled = selected == 1; flashEnabledAt = millis();
    digitalWrite(FLASH_LED_GPIO_NUM, flashEnabled ? HIGH : LOW);
  } else if (!strcmp(name, "framesize") && (selected == FRAMESIZE_QVGA || selected == FRAMESIZE_VGA || selected == FRAMESIZE_SVGA)) {
    if (xSemaphoreTake(cameraMutex, pdMS_TO_TICKS(3000)) != pdTRUE) return busy(req);
    const int result = esp_camera_sensor_get()->set_framesize(esp_camera_sensor_get(), static_cast<framesize_t>(selected));
    xSemaphoreGive(cameraMutex);
    if (result != 0) return httpd_resp_send_err(req, HTTPD_500_INTERNAL_SERVER_ERROR, "Resolution failed");
  } else return httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "Unsupported control");
  return httpd_resp_send(req, "OK", HTTPD_RESP_USE_STRLEN);
}
esp_err_t streamHandler(httpd_req_t *req) {
  if (!authorized(req)) return ESP_OK;
  httpd_resp_set_type(req, "multipart/x-mixed-replace;boundary=frame");
  while (WiFi.status() == WL_CONNECTED) {
    if (xSemaphoreTake(cameraMutex, pdMS_TO_TICKS(1000)) != pdTRUE) break;
    camera_fb_t *frame = esp_camera_fb_get();
    if (!frame) { xSemaphoreGive(cameraMutex); break; }
    char header[96];
    const int length = snprintf(header, sizeof(header), "\r\n--frame\r\nContent-Type: image/jpeg\r\nContent-Length: %u\r\n\r\n", unsigned(frame->len));
    esp_err_t result = httpd_resp_send_chunk(req, header, length);
    if (result == ESP_OK) result = httpd_resp_send_chunk(req, reinterpret_cast<const char *>(frame->buf), frame->len);
    esp_camera_fb_return(frame); xSemaphoreGive(cameraMutex);
    if (result != ESP_OK) break;
    vTaskDelay(pdMS_TO_TICKS(100));
  }
  httpd_resp_send_chunk(req, nullptr, 0);
  return ESP_OK;
}
void route(httpd_handle_t server, const char *path, esp_err_t (*handler)(httpd_req_t *)) {
  httpd_uri_t get = {}; get.uri = path; get.method = HTTP_GET; get.handler = handler;
  httpd_register_uri_handler(server, &get);
  httpd_uri_t preflight = {}; preflight.uri = path; preflight.method = HTTP_OPTIONS; preflight.handler = optionsHandler;
  httpd_register_uri_handler(server, &preflight);
}
bool startServers() {
  MDNS.begin("esp32cam");
  httpd_config_t controls = HTTPD_DEFAULT_CONFIG();
  controls.server_port = 81; controls.ctrl_port = 32769; controls.stack_size = 8192;
  controls.lru_purge_enable = true; controls.send_wait_timeout = 3; controls.recv_wait_timeout = 3;
  if (httpd_start(&controlServer, &controls) != ESP_OK) return false;
  route(controlServer, "/capture", captureHandler); route(controlServer, "/control", controlHandler);
  httpd_config_t stream = HTTPD_DEFAULT_CONFIG();
  stream.server_port = 80; stream.ctrl_port = 32768; stream.stack_size = 8192;
  stream.send_wait_timeout = 3; stream.recv_wait_timeout = 3;
  if (httpd_start(&streamServer, &stream) != ESP_OK) { httpd_stop(controlServer); controlServer = nullptr; return false; }
  route(streamServer, "/stream", streamHandler);
  return true;
}
void setup() {
  Serial.begin(115200); pinMode(FLASH_LED_GPIO_NUM, OUTPUT); digitalWrite(FLASH_LED_GPIO_NUM, LOW);
  if (strlen(CAMERA_PASSWORD) < 16) { Serial.println("Set a camera password of at least 16 characters."); return; }
  const String credentials = String("camera:") + CAMERA_PASSWORD;
  unsigned char encoded[256]; size_t length = 0;
  if (mbedtls_base64_encode(encoded, sizeof(encoded) - 1, &length, reinterpret_cast<const unsigned char *>(credentials.c_str()), credentials.length()) != 0) return;
  encoded[length] = 0; expectedAuth = String("Basic ") + reinterpret_cast<char *>(encoded);
  camera_config_t c = {};
  c.ledc_channel = LEDC_CHANNEL_0; c.ledc_timer = LEDC_TIMER_0;
  c.pin_d0 = Y2_GPIO_NUM; c.pin_d1 = Y3_GPIO_NUM; c.pin_d2 = Y4_GPIO_NUM; c.pin_d3 = Y5_GPIO_NUM;
  c.pin_d4 = Y6_GPIO_NUM; c.pin_d5 = Y7_GPIO_NUM; c.pin_d6 = Y8_GPIO_NUM; c.pin_d7 = Y9_GPIO_NUM;
  c.pin_xclk = XCLK_GPIO_NUM; c.pin_pclk = PCLK_GPIO_NUM; c.pin_vsync = VSYNC_GPIO_NUM; c.pin_href = HREF_GPIO_NUM;
  c.pin_sccb_sda = SIOD_GPIO_NUM; c.pin_sccb_scl = SIOC_GPIO_NUM; c.pin_pwdn = PWDN_GPIO_NUM; c.pin_reset = RESET_GPIO_NUM;
  c.xclk_freq_hz = 20000000; c.pixel_format = PIXFORMAT_JPEG;
  c.frame_size = FRAMESIZE_VGA; c.jpeg_quality = 12; c.fb_count = psramFound() ? 2 : 1;
  c.grab_mode = CAMERA_GRAB_LATEST;
  if (esp_camera_init(&c) != ESP_OK) { Serial.println("Camera initialization failed. Check power and pinout, then restart."); return; }
  cameraMutex = xSemaphoreCreateMutex();
  if (!cameraMutex) return;
  WiFi.mode(WIFI_STA); WiFi.setAutoReconnect(true); WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
}
void loop() {
  if (flashEnabled && millis() - flashEnabledAt > 30000) { digitalWrite(FLASH_LED_GPIO_NUM, LOW); flashEnabled = false; }
  static uint32_t lastAttempt = 0;
  if (cameraMutex && expectedAuth.length() && !streamServer && WiFi.status() == WL_CONNECTED && millis() - lastAttempt > 5000) {
    lastAttempt = millis();
    if (startServers()) { Serial.print("Camera stream http://"); Serial.print(WiFi.localIP()); Serial.println("/stream (controls on port 81)"); }
  }
  delay(20);
}
