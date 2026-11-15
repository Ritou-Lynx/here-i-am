// CAM1 pan-tilt mount for the bedside phone. ESP32 + two hobby servos, LAN HTTP only.
// Libraries: ESP32 board package (Espressif) and "ESP32Servo" (Arduino Library Manager).
// Endpoints (all answers are small JSON):
//   GET  /health                         -> {"ok":true,"pan":90,"tilt":90}
//   POST /move?pan=<deg>&tilt=<deg>      -> moves smoothly, answers when settled; needs header X-Gimbal-Token
//   POST /relax                          -> stops driving both servos (quiet); needs X-Gimbal-Token
// No camera, no image, no cloud. The phone does all looking; this board only turns.
#include <WiFi.h>
#include <WebServer.h>
#include <Preferences.h>
#include <ESP32Servo.h>
#include "wifi_config.h"

// ---- wiring: servo signal pins on the expansion board ----
const int PAN_PIN = 18;   // left/right servo
const int TILT_PIN = 19;  // up/down servo (the one carrying the phone)
// ---- mechanical limits (degrees). Narrow these if the cable or bracket hits something. ----
const int PAN_MIN = 0, PAN_MAX = 180;
const int TILT_MIN = 40, TILT_MAX = 140;
const int STEP_MS = 12;        // time per degree; larger = slower and steadier
const int SETTLE_MS = 350;     // hold after arriving so the phone stops shaking
const int RELAX_AFTER_MS = 4000; // stop driving the servos this long after the last move

WebServer server(80);
Preferences prefs;
Servo panServo, tiltServo;
int panNow = 90, tiltNow = 90;
unsigned long lastMoveAt = 0;
bool driving = false;

static bool tokenOk() {
  String got = server.header("X-Gimbal-Token");
  const char *want = GIMBAL_TOKEN;
  size_t n = strlen(want);
  if (n < 16 || got.length() != n) return false;
  uint8_t diff = 0;
  for (size_t i = 0; i < n; i++) diff |= (uint8_t)got[i] ^ (uint8_t)want[i];
  return diff == 0;
}

static void reply(int code, const String &json) {
  server.sendHeader("Cache-Control", "no-store");
  server.send(code, "application/json", json);
}

static String state() { return String("{\"ok\":true,\"pan\":") + panNow + ",\"tilt\":" + tiltNow + "}"; }

static void attachAll() {
  if (driving) return;
  // Write the remembered angle first so attaching does not jump.
  panServo.write(panNow); tiltServo.write(tiltNow);
  panServo.attach(PAN_PIN, 500, 2500);
  tiltServo.attach(TILT_PIN, 500, 2500);
  panServo.write(panNow); tiltServo.write(tiltNow);
  driving = true;
}

static void relaxAll() {
  if (!driving) return;
  panServo.detach(); tiltServo.detach();
  driving = false;
}

static void moveTo(int pan, int tilt) {
  pan = constrain(pan, PAN_MIN, PAN_MAX);
  tilt = constrain(tilt, TILT_MIN, TILT_MAX);
  attachAll();
  while (panNow != pan || tiltNow != tilt) {
    if (panNow != pan) panNow += pan > panNow ? 1 : -1;
    if (tiltNow != tilt) tiltNow += tilt > tiltNow ? 1 : -1;
    panServo.write(panNow); tiltServo.write(tiltNow);
    delay(STEP_MS);
  }
  delay(SETTLE_MS);
  prefs.putInt("pan", panNow); prefs.putInt("tilt", tiltNow);
  lastMoveAt = millis();
}

static bool readAngle(const char *name, int current, int &out) {
  if (!server.hasArg(name)) { out = current; return true; }
  String v = server.arg(name);
  if (v.length() < 1 || v.length() > 3) return false;
  for (size_t i = 0; i < v.length(); i++) if (!isDigit(v[i])) return false;
  out = v.toInt();
  return out >= 0 && out <= 180;
}

static void handleMove() {
  if (!tokenOk()) { reply(401, "{\"error\":\"unauthorized\"}"); return; }
  int pan, tilt;
  if (!readAngle("pan", panNow, pan) || !readAngle("tilt", tiltNow, tilt)) { reply(400, "{\"error\":\"invalid_angle\"}"); return; }
  moveTo(pan, tilt);
  reply(200, state());
}

static void handleRelax() {
  if (!tokenOk()) { reply(401, "{\"error\":\"unauthorized\"}"); return; }
  relaxAll();
  reply(200, state());
}

static void connectWifi() {
  WiFi.mode(WIFI_STA);
  WiFi.setHostname("linai-gimbal");
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  for (int i = 0; i < 60 && WiFi.status() != WL_CONNECTED; i++) delay(500);
  if (WiFi.status() == WL_CONNECTED) {
    Serial.print("gimbal ready at http://"); Serial.println(WiFi.localIP());
  } else {
    Serial.println("wifi not connected yet; will keep retrying");
  }
}

void setup() {
  Serial.begin(115200);
  prefs.begin("gimbal", false);
  panNow = constrain(prefs.getInt("pan", 90), PAN_MIN, PAN_MAX);
  tiltNow = constrain(prefs.getInt("tilt", 90), TILT_MIN, TILT_MAX);
  ESP32PWM::allocateTimer(0); ESP32PWM::allocateTimer(1);
  panServo.setPeriodHertz(50); tiltServo.setPeriodHertz(50);
  connectWifi();
  const char *headers[] = {"X-Gimbal-Token"};
  server.collectHeaders(headers, 1);
  server.on("/health", HTTP_GET, []() { reply(200, state()); });
  server.on("/move", HTTP_POST, handleMove);
  server.on("/relax", HTTP_POST, handleRelax);
  server.onNotFound([]() { reply(404, "{\"error\":\"not_found\"}"); });
  server.begin();
}

void loop() {
  static unsigned long lastWifiTry = 0;
  if (WiFi.status() != WL_CONNECTED && millis() - lastWifiTry > 10000) {
    lastWifiTry = millis();
    WiFi.disconnect(); WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  }
  server.handleClient();
  if (driving && millis() - lastMoveAt > (unsigned long)RELAX_AFTER_MS) relaxAll();
  delay(2);
}
