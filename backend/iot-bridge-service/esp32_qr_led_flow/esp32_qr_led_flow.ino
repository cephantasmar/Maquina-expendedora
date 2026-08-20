#include <WiFi.h>
#include <HTTPClient.h>
#include <WebServer.h>
#include <TFT_eSPI.h>
#include "qrcode.h"
#include <Keypad.h>
#include <DHT.h> 
#include <Preferences.h> // MEMORIA PERMANENTE

TFT_eSPI tft = TFT_eSPI();
Preferences preferences; // Objeto para manejar la memoria

const byte ROWS = 4, COLS = 4;
char keys[ROWS][COLS] = {
  {'1','2','3','A'},
  {'4','5','6','B'},
  {'7','8','9','C'},
  {'*','0','#','D'}
};
byte rowPins[ROWS] = {26, 25, 33, 32};
byte colPins[COLS] = {13, 12, 14, 27};
Keypad keypad = Keypad(makeKeymap(keys), colPins, rowPins, ROWS, COLS);

// Definir LED_BUILTIN si no está definido
#ifndef LED_BUILTIN
#define LED_BUILTIN 2
#endif

// Usamos GPIO 2 (LED integrado) para las luces.
// El TFT_DC está en el GPIO 21 según tu configuración.
const int LED_PIN = LED_BUILTIN; 
// RE-ASIGNADOS: 5 y 22 para no chocar con TFT_RST(4) y TFT_CS(15)
const int TRIG_PIN = 5, ECHO_PIN = 22; 

#define DHTPIN 19     
#define DHTTYPE DHT11 
DHT dht(DHTPIN, DHTTYPE);

float distanciaInicial = 0.0, distanciaFinal = 0.0;
float prevM1 = 0.0, prevM2 = 0.0;
const float UMBRAL_CAIDA_CM = 3.0; 
// ==========================================================

// ================= CONFIGURACION SISTEMA ==================
const char* WIFI_SSID = "ar-HP-Laptop-15-da2xxx";
const char* WIFI_PASSWORD = "123456789";
String SERVER_IP = "10.42.0.1"; 
const char* MACHINE_ID = "MACHINE-001";
const int WEBHOOK_PORT = 8081;
const unsigned long POLL_INTERVAL_MS = 1500;
const unsigned long TELEMETRY_INTERVAL_MS = 5000; 
// ==========================================================

WebServer webhookServer(WEBHOOK_PORT);
String currentTxId = "", inputCodigo = "", precioSeleccionado = "10.00";
unsigned long lastPoll = 0;
unsigned long lastPollCommands = 0; // NUEVO: Para el polling de comandos
unsigned long lastTelemetry = 0;
unsigned long lastActivityTime = 0; // NUEVO: Para el temporizador de inactividad
bool webhookPaymentPending = false;
bool waitingForPayment = false;

String baseUrl() { return String("http://") + SERVER_IP + ":8010"; }
String vendingUrl() { return String("http://") + SERVER_IP + ":8040"; }

// --- UTILIDADES ---
void mostrarCatalogo(); // Prototipo

void resetState() {
  inputCodigo = "";
  currentTxId = "";
  waitingForPayment = false;
  lastActivityTime = millis();
  mostrarCatalogo();
}

void pedirIP() {
  tft.fillScreen(TFT_BLACK);
  tft.setTextColor(TFT_GREEN);
  tft.setTextSize(2);
  tft.setCursor(10, 5);
  tft.println("MI IP ESP32:");
  tft.setCursor(10, 25);
  tft.setTextColor(TFT_YELLOW);
  tft.println(WiFi.localIP());

  tft.setCursor(10, 55);
  tft.setTextColor(TFT_GREEN);
  tft.println("IP SERVER:");
  tft.setCursor(10, 75);
  tft.setTextColor(TFT_WHITE);
  tft.setTextSize(1);
  tft.println("Use '*' para punto '.'");
  tft.println("Use 'D' confirmar, 'C' borrar");
  tft.drawRect(10, 100, 220, 40, TFT_WHITE);
  
  String nuevaIP = "";
  while (true) {
    char key = keypad.getKey();
    if (key) {
      if (key == 'D') {
        if (nuevaIP.length() > 7) { 
          SERVER_IP = nuevaIP;
          preferences.begin("grog", false);
          preferences.putString("server_ip", SERVER_IP); 
          preferences.end();
          break;
        }
      } else if (key == '*') {
        nuevaIP += ".";
      } else if (key == 'C') {
        if (nuevaIP.length() > 0) nuevaIP.remove(nuevaIP.length() - 1);
      } else if (key >= '0' && key <= '9') {
        nuevaIP += key;
      }
      
      tft.fillRect(15, 105, 210, 30, TFT_BLACK);
      tft.setCursor(20, 110);
      tft.setTextColor(TFT_YELLOW);
      tft.setTextSize(2);
      tft.print(nuevaIP);
      tft.print("_");
    }
    delay(10);
  }
  tft.fillScreen(TFT_BLACK);
  tft.setCursor(10, 100);
  tft.setTextColor(TFT_GREEN);
  tft.println("IP CONFIGURADA!");
  delay(1000);
}

void mostrarTeclaEnPantalla(char key) {
  int rectWidth = 40, rectHeight = 40;
  int xPos = tft.width() - rectWidth - 5, yPos = 5; // Arriba a la derecha
  tft.fillRect(xPos, yPos, rectWidth, rectHeight, TFT_BLUE);
  tft.drawRect(xPos, yPos, rectWidth, rectHeight, TFT_WHITE);
  tft.setTextColor(TFT_WHITE, TFT_BLUE); tft.setTextSize(3);
  tft.setCursor(xPos + 12, yPos + 10); tft.print(key);
}

float medirDistancia() {
  // Asegurar que el pin esté limpio antes del pulso
  digitalWrite(TRIG_PIN, LOW); 
  delayMicroseconds(5);
  
  digitalWrite(TRIG_PIN, HIGH); 
  delayMicroseconds(10);
  digitalWrite(TRIG_PIN, LOW);
  
  // Timeout reducido para máxima velocidad de muestreo
  long duration = pulseIn(ECHO_PIN, HIGH, 5000); 
  
  if (duration == 0) {
    // Si da 0, intentamos una vez más tras un pequeño delay
    delayMicroseconds(200);
    digitalWrite(TRIG_PIN, HIGH); delayMicroseconds(10); digitalWrite(TRIG_PIN, LOW);
    duration = pulseIn(ECHO_PIN, HIGH, 5000);
  }

  float cm = (duration * 0.0343) / 2.0;
  
  // Debug por Serial si hay error persistente
  if (duration == 0) {
    Serial.println("[SENSOR] Error: Sin pulso de ECO (¿está conectado?)");
    return 400.0;
  }
  
  if (cm < 1.0) return 0.0; // Objeto demasiado cerca
  if (cm > 400.0) return 400.0; // Fuera de rango
  
  return cm;
}

void dibujarMonitores(float temp = -1.0) {
  // Monitores actuales (Abajo a la derecha)
  int x = tft.width() - 85, y = tft.height() - 65; 
  tft.fillRect(x, y, 80, 60, TFT_BLACK); tft.drawRect(x, y, 80, 60, TFT_DARKGREY);
  tft.setTextSize(1);
  tft.setTextColor(TFT_CYAN); tft.setCursor(x+5, y+5); tft.print("M1:"); tft.print(distanciaInicial,1);
  tft.setTextColor(TFT_MAGENTA); tft.setCursor(x+5, y+25); tft.print("M2:"); tft.print(distanciaFinal,1);
  if (temp > -1.0) {
    tft.setTextColor(TFT_YELLOW); tft.setCursor(x+5, y+45); tft.print("T:"); tft.print(temp,1); tft.print("C");
  }

  // Histórico / Datos anteriores (Arriba a la derecha)
  int hX = tft.width() - 120, hY = 5;
  tft.fillRect(hX, hY, 115, 25, TFT_BLACK);
  tft.drawRect(hX, hY, 115, 25, TFT_DARKGREY);
  tft.setTextSize(1);
  tft.setTextColor(TFT_LIGHTGREY);
  tft.setCursor(hX+5, hY+10);
  tft.printf("P:M1:%.1f M2:%.1f", prevM1, prevM2);
}

String extractTxId(const String& body) {
  int i = body.indexOf("\"tx_id\":\"");
  if (i < 0) i = body.indexOf("\"tx_id\": \"");
  if (i < 0) i = body.indexOf("\"id\":\"");
  if (i < 0) return "";
  int start = body.indexOf("\"", i + 8) + 1;
  return body.substring(start, body.indexOf("\"", start));
}

void enviarTelemetria(float temp) {
  HTTPClient http;
  String url = baseUrl() + "/api/v1/machines/" + MACHINE_ID + "/telemetry";
  http.begin(url);
  http.addHeader("Content-Type", "application/json");
  String body = "{\"temperature\":" + String(temp) + ", \"ip\":\"" + WiFi.localIP().toString() + "\"}";
  http.POST(body);
  http.end();
}

void mostrarCatalogo() {
  tft.fillScreen(TFT_BLACK);
  tft.setTextColor(TFT_CYAN); tft.setTextSize(2); tft.setCursor(10, 10); tft.println("GROG VENDING");
  tft.drawFastHLine(0, 35, tft.width(), TFT_WHITE);
  
  if (WiFi.status() != WL_CONNECTED) {
    tft.setTextColor(TFT_RED); tft.setCursor(10, 50); tft.println("SIN CONEXION WIFI");
    return;
  }

  HTTPClient http;
  http.setTimeout(10000); 
  String url = vendingUrl() + "/api/v1/machines/" + MACHINE_ID + "/inventory";
  
  // Serial.print("PIDIENDO CATÁLOGO A: "); Serial.println(url);
  
  http.begin(url);
  int httpCode = http.GET();
  
  if (httpCode == 200) {
    String payload = http.getString(); 
    // Serial.println("RESPUESTA RECIBIDA.");
    int pos = 0, y = 50;
    while ((pos = payload.indexOf("\"slot\":", pos)) != -1 && y < (tft.height() - 40)) {
      yield(); 
      int sS = payload.indexOf("\"", pos + 7) + 1; 
      String slot = payload.substring(sS, payload.indexOf("\"", sS));
      int nPos = payload.indexOf("\"product_name\":", pos); 
      int nS = payload.indexOf("\"", nPos + 15) + 1; 
      String name = payload.substring(nS, payload.indexOf("\"", nS));
      int pPos = payload.indexOf("\"price\":", pos); 
      int pS = payload.indexOf(":", pPos) + 1; 
      while(pS < payload.length() && (payload[pS] == ' ' || payload[pS] == '\"')) pS++;
      int pE = pS; 
      while(pE < payload.length() && payload[pE] != ',' && payload[pE] != '}' && payload[pE] != '\"' && payload[pE] != ' ') pE++;
      String price = payload.substring(pS, pE);
      
      tft.setCursor(10, y); tft.setTextSize(2);
      tft.setTextColor(TFT_YELLOW); tft.print(slot);
      tft.setTextColor(TFT_WHITE); tft.print(": "); 
      tft.print(name.substring(0, 10)); 
      tft.setTextColor(TFT_GREEN); tft.print(" Bs"); tft.println(price);
      y += 30; pos = pPos + 5; 
    }
  } else {
    Serial.print("ERROR HTTP: "); Serial.println(httpCode);
    tft.setCursor(10, 50); tft.setTextColor(TFT_RED); tft.print("ERROR: "); tft.print(httpCode);
  }
  http.end();
  
  // LEYENDA DINAMICA EN CATALOGO
  tft.fillRect(0, tft.height()-45, tft.width(), 45, TFT_BLACK);
  tft.drawFastHLine(0, tft.height()-45, tft.width(), TFT_DARKGREY);
  tft.setTextSize(1); tft.setTextColor(TFT_LIGHTGREY); 
  tft.setCursor(10, tft.height()-35); tft.print("D: COMPRAR   *: LIMPIAR");
  tft.setCursor(10, tft.height()-20); tft.print("CODIGOS: A1-A3, A7, C1-C3, C7");
  
  dibujarMonitores();
}

bool lightsOn = false;

void toggleLights() {
  lightsOn = !lightsOn;
  digitalWrite(LED_PIN, lightsOn ? HIGH : LOW);
  Serial.print("Luces: "); Serial.println(lightsOn ? "ENCENDIDAS" : "APAGADAS");
}

void registrarIntencionYMostrarQR() {
  lastActivityTime = millis();
  HTTPClient http;
  
  // 1. Obtener info del slot y verificar si está habilitado
  String slotUrl = vendingUrl() + "/api/v1/machines/" + MACHINE_ID + "/slots/" + inputCodigo;
  http.begin(slotUrl);
  int httpCode = http.GET();
  bool canBuy = false;
  
  if (httpCode == 200) {
    String payload = http.getString(); 
    // Buscar "is_enabled":true
    if (payload.indexOf("\"is_enabled\":true") != -1) {
      canBuy = true;
      // Extraer precio
      int pP = payload.indexOf("\"price\":"); 
      int pS = payload.indexOf(":", pP) + 1;
      while(pS < payload.length() && (payload[pS] == ' ' || payload[pS] == '\"')) pS++;
      int pE = pS;
      while(pE < payload.length() && payload[pE] != ',' && payload[pE] != '}' && payload[pE] != '\"' && payload[pE] != ' ') pE++;
      precioSeleccionado = payload.substring(pS, pE);
    }
  }
  http.end();

  if (!canBuy) {
    tft.fillScreen(TFT_BLACK);
    tft.setTextColor(TFT_RED); tft.setTextSize(2);
    tft.setCursor(10, 80);
    tft.println("SLOT NO DISPONIBLE");
    tft.setTextColor(TFT_WHITE);
    tft.println("POR FAVOR ELIJA OTRO");
    delay(3000);
    resetState();
    return;
  }

  // 2. Registrar transaccion en orquestador
  http.begin(baseUrl() + "/api/v1/transactions/init");
  http.addHeader("Content-Type", "application/json");
  String regBody = "{\"machine_id\":\"" + String(MACHINE_ID) + "\",\"product_id\":\"" + inputCodigo + "\",\"amount\":" + precioSeleccionado + "}";
  if (http.POST(regBody) == 200) {
    currentTxId = extractTxId(http.getString());
  }
  http.end();

  distanciaInicial = medirDistancia();
  tft.fillScreen(TFT_WHITE); tft.setTextColor(TFT_BLACK); tft.setTextSize(2); tft.setCursor(10, 5);
  tft.printf("PAGAR %s: Bs%s", inputCodigo.c_str(), precioSeleccionado.c_str());
  
  // 3. Generar y mostrar QR
  String payload = baseUrl() + "/init/" + MACHINE_ID + "?product_id=" + inputCodigo + "&amount=" + precioSeleccionado;
  esp_qrcode_config_t cfg = ESP_QRCODE_CONFIG_DEFAULT();
  cfg.display_func = [](esp_qrcode_handle_t qrcode) {
    int qrSize = esp_qrcode_get_size(qrcode); int scale = 4;
    int sX = (tft.width() - (qrSize * scale)) / 2; int sY = (tft.height() - (qrSize * scale)) / 2 + 10;
    for (int y = 0; y < qrSize; y++) {
      for (int x = 0; x < qrSize; x++) {
        tft.fillRect(sX + (x * scale), sY + (y * scale), scale, scale, esp_qrcode_get_module(qrcode, x, y) ? TFT_BLACK : TFT_WHITE);
      }
    }
  };
  esp_qrcode_generate(&cfg, payload.c_str());
  
  // LEYENDA EN PANTALLA QR
  tft.fillRect(0, tft.height()-30, tft.width(), 30, TFT_BLACK);
  tft.setTextColor(TFT_YELLOW); tft.setTextSize(1);
  tft.setCursor(20, tft.height()-20); tft.print("PRESIONE '*' PARA CANCELAR");
  
  waitingForPayment = true;
  dibujarMonitores();
}
void processPaidTransaction(String txId) {
  Serial.println("\n[SYSTEM] --- INICIANDO PROCESO DE DESPACHO (MODO RÁFAGA) ---");
  Serial.printf("[SYSTEM] TX ID: %s | Slot: %s\n", txId.c_str(), inputCodigo.c_str());

  // Guardar históricos para la pantalla antes de actualizar
  prevM1 = distanciaInicial;
  prevM2 = distanciaFinal;

  // Asegurar que M1 (Base) es válida
  if (distanciaInicial > 390.0) {
    distanciaInicial = medirDistancia();
    Serial.printf("[SENSOR] Calibrando M1 (Base): %.2f cm\n", distanciaInicial);
  }

  waitingForPayment = false;
  tft.fillScreen(TFT_BLACK); 
  tft.setTextColor(TFT_YELLOW); tft.setTextSize(2); tft.setCursor(10, 20);
  tft.println("PAGO CONFIRMADO"); 
  tft.setTextColor(TFT_WHITE); tft.println("INICIANDO MOTOR...");

  // 1. MANDAR SEÑAL AL ESCLAVO
  Serial.printf("[SLAVE] >>> Enviando MOVE:%s\n", inputCodigo.c_str());
  Serial2.println("MOVE:" + inputCodigo);

  // 2. MONITOREO EN RÁFAGA CON CONTEO REGRESIVO (10 SEGUNDOS)
  distanciaFinal = distanciaInicial; // M2 empieza siendo igual a la base
  bool detectado = false;
  unsigned long startBurst = millis();
  int lastSec = -1;

  Serial.println("[SENSOR] Iniciando ráfaga de medidas (10s)...");

  while (millis() - startBurst < 10000) {
    unsigned long elapsed = millis() - startBurst;
    int secondsLeft = 10 - (elapsed / 1000);

    // Actualizar cuenta regresiva en pantalla (sin parpadeo)
    if (secondsLeft != lastSec) {
      lastSec = secondsLeft;
      tft.fillRect(0, 80, tft.width(), 40, TFT_BLACK); // Limpiar franja del contador
      tft.setCursor(20, 90);
      tft.setTextColor(TFT_CYAN); tft.setTextSize(2);
      tft.printf("VIGILANDO: %ds", secondsLeft);
      Serial.printf("[SYSTEM] Tiempo restante: %ds...\n", secondsLeft);
    }

    // Medida a alta velocidad
    float d = medirDistancia();
    
    // Mostramos cada medida en el serial para análisis
    Serial.printf("[RAFAGA] Dist: %.2f cm\n", d);

    if (d > 0.5 && d < 350.0) {
      // Buscamos el valor más bajo (M2)
      if (d < distanciaFinal) {
        distanciaFinal = d;
        // Si detectamos algo por debajo del umbral, ya podemos marcarlo como éxito interno
        if (distanciaFinal < (distanciaInicial - UMBRAL_CAIDA_CM)) {
          detectado = true;
        }
      }
    }

    // Revisar si el esclavo responde DONE mientras medimos
    if (Serial2.available()) {
      String resp = Serial2.readStringUntil('\n');
      resp.trim();
      if (resp == "DONE") Serial.println("[SLAVE] Motor terminó su giro.");
    }

    delay(10); // Pausa mínima para no saturar el procesador pero mantener ráfaga alta
  }

  // 3. DETERMINAR RESULTADO FINAL
  // Si en algún momento de la ráfaga el valor bajó lo suficiente, detectado será true
  if (distanciaFinal < (distanciaInicial - UMBRAL_CAIDA_CM)) {
    detectado = true;
  }

  Serial.printf("[SENSOR] RESUMEN -> M1 (Base): %.2f | M2 (Min): %.2f\n", distanciaInicial, distanciaFinal);

  // MOSTRAR RESULTADO EN TFT
  tft.fillScreen(TFT_BLACK);
  if (detectado) {
    tft.setCursor(10, 80);
    tft.setTextColor(TFT_GREEN); tft.setTextSize(3); tft.println("¡EXITO!");
    tft.setTextSize(2); tft.println("PRODUCTO ENTREGADO");
    Serial.println("[RESULT] Despacho exitoso (Detección en ráfaga).");
  } else {
    tft.setCursor(10, 60);
    tft.setTextColor(TFT_RED); tft.setTextSize(3); tft.println("ERROR");
    tft.setTextSize(2);
    tft.println("NO SE DETECTO");
    tft.println("LA CAIDA DEL");
    tft.println("PRODUCTO");
    Serial.println("[RESULT] No se detectó ninguna caída significante.");
  }

  // 4. NOTIFICAR AL BACKEND (M1 y M2-mínimo)
  if (WiFi.status() == WL_CONNECTED) {
    HTTPClient http;
    String endPoint = detectado ? "/dispense-result" : "/refund";
    String url = baseUrl() + "/api/v1/transactions/" + txId + endPoint;
    
    Serial.printf("[HTTP] Notificando a: %s\n", url.c_str());
    http.begin(url);
    http.addHeader("Content-Type", "application/json");
    
    // Enviamos M1 como initial_distance y el M2 más bajo como final_distance
    String telemetry = "{\"success\":" + String(detectado?"true":"false") + 
                       ",\"initial_distance\":" + String(distanciaInicial) + 
                       ",\"final_distance\":" + String(distanciaFinal) + "}";
    
    int httpCode = http.POST(telemetry);
    if (httpCode > 0) {
      Serial.printf("[HTTP] Code: %d\n", httpCode);
    }
    http.end();
  }

  Serial.println("[SYSTEM] --- FIN DEL PROCESO ---\n");
  dibujarMonitores();
  delay(3000);
  resetState();
}

void connectWifi() {
  Serial.print("Conectando a: "); Serial.println(WIFI_SSID);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  int retry = 0;
  while (WiFi.status() != WL_CONNECTED && retry < 20) { 
    delay(500); 
    Serial.print("."); 
    retry++;
  }
  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\nWiFi OK");
  } else {
    Serial.println("\nError: WiFi no conectado.");
  }
}

void setup() {
  Serial.begin(115200);
  // Inicializar Serial2 para el Esclavo (RX=16, TX=17)
  Serial2.begin(9600, SERIAL_8N1, 16, 17); 
  delay(1000);
  Serial.println("--- MASTER INICIADO ---");

  pinMode(TRIG_PIN, OUTPUT); pinMode(ECHO_PIN, INPUT); pinMode(LED_PIN, OUTPUT);
  
  tft.init(); tft.setRotation(0);
  tft.fillScreen(TFT_BLACK);
  tft.setTextColor(TFT_CYAN);
  tft.setTextSize(3);
  tft.setCursor(20, 80);
  tft.println("BIENVENIDO");
  tft.setCursor(60, 120);
  tft.setTextColor(TFT_YELLOW);
  tft.println("A GROG");
  
  // Intentar conectar mientras se muestra la bienvenida
  connectWifi();
  delay(2000); 

  Serial.println("Configurando IP fija...");
  SERVER_IP = "10.42.0.1";
  /*
  Serial.println("Cargando configuracion...");
  preferences.begin("grog", true); 
  String savedIP = preferences.getString("server_ip", ""); 
  preferences.end();
  
  if (savedIP != "") SERVER_IP = savedIP;
  */
  
  dht.begin(); 
  
  webhookServer.on("/payment-confirmed", HTTP_POST, [](){
    String txId = webhookServer.arg("tx_id");
    if (txId.length() > 0) { currentTxId = txId; webhookPaymentPending = true; }
    webhookServer.send(200, "application/json", "{\"ok\":true}");
  });
  
  webhookServer.on("/command", HTTP_POST, [](){
    String cmd = webhookServer.arg("command");
    if (cmd == "toggle_lights") { toggleLights(); }
    else if (cmd == "lights_on") { lightsOn = false; toggleLights(); }
    else if (cmd == "lights_off") { lightsOn = true; toggleLights(); }
    webhookServer.send(200, "application/json", "{\"ok\":true}");
  });

  webhookServer.begin();
  lastActivityTime = millis();
  
  Serial.println("Cargando Catalogo...");
  mostrarCatalogo();
}

void loop() {
  webhookServer.handleClient();
  if (webhookPaymentPending) { webhookPaymentPending = false; processPaidTransaction(currentTxId); }
  
  unsigned long now = millis();

  // TEMPORIZADOR DE INACTIVIDAD (1 MINUTO)
  if ((inputCodigo.length() > 0 || waitingForPayment) && (now - lastActivityTime > 60000)) {
    resetState();
  }

  if (now - lastTelemetry >= TELEMETRY_INTERVAL_MS) {
    lastTelemetry = now;
    float t = dht.readTemperature();
    if (!isnan(t)) { enviarTelemetria(t); dibujarMonitores(t); }
  }

  if (waitingForPayment && (now - lastPoll >= POLL_INTERVAL_MS)) {
    lastPoll = now;
    if (WiFi.status() == WL_CONNECTED) {
      HTTPClient http; http.begin(baseUrl() + "/api/v1/machines/" + MACHINE_ID + "/next-paid");
      if (http.GET() == 200) {
        String res = http.getString();
        if (res.indexOf("\"tx_id\":\"") != -1) processPaidTransaction(extractTxId(res));
      }
      http.end();
    }
  }

  // Polling de comandos para luces y actualización de catálogo (Precios)
  if (now - lastPollCommands >= 3000) {
    lastPollCommands = now;
    if (WiFi.status() == WL_CONNECTED) {
      HTTPClient http;
      http.begin(baseUrl() + "/api/v1/admin/commands/poll/" + String(MACHINE_ID));
      if (http.GET() == 200) {
        String payload = http.getString();
        // Solo refrescamos si el payload contiene comandos reales (no una lista vacía)
        if (payload.indexOf("\"commands\":[]") == -1) {
          if (payload.indexOf("toggle_lights") != -1) {
            toggleLights();
          }
          if (payload.indexOf("lights_on") != -1) {
            lightsOn = false; toggleLights();
          }
          if (payload.indexOf("lights_off") != -1) {
            lightsOn = true; toggleLights();
          }
          if (payload.indexOf("refresh_inventory_config") != -1) {
            mostrarCatalogo();
          }
        }
      }
      http.end();
    }
  }

  char key = keypad.getKey();
  if (key) {
    lastActivityTime = now;
    mostrarTeclaEnPantalla(key);
    
    if (key == 'D') { 
      if (inputCodigo.length() > 0) registrarIntencionYMostrarQR(); 
    }
    else if (key == '*') { 
       resetState(); 
    }
    else {
      // 'A', 'B', 'C' y números se guardan en el código
      inputCodigo += key;
      tft.fillRect(10, 180, 180, 40, TFT_NAVY); tft.drawRect(10, 180, 180, 40, TFT_WHITE);
      tft.setCursor(20, 190); tft.setTextColor(TFT_WHITE); tft.setTextSize(2); tft.print("COD: "); tft.print(inputCodigo);
      dibujarMonitores();
    }
  }
}
