/**
 * ESP32 SLAVE - CONTROL DE MOTORES PAP (STEPPER)
 * Recibe comandos por Serial2 del ESP32 Maestro.
 * Controla 8 drivers A4988/DRV8825.
 */

// ================= CONFIGURACION PINES =================
const int PIN_ENABLE = 4; // ENABLE compartido para todos los motores

// Estructura para definir los pines de cada motor
struct Stepper {
  int stepPin;
  int dirPin;
};

// Mapeo de 8 motores
Stepper motors[8] = {
  {5,  18}, // Motor 1 (Ej: Slot A1)
  {19, 21}, // Motor 2 (Ej: Slot A2)
  {22, 23}, // Motor 3
  {25, 26}, // Motor 4
  {27, 32}, // Motor 5
  {33, 12}, // Motor 6
  {13, 14}, // Motor 7
  {2,  15}  // Motor 8
};

const int STEPS_PER_REV = 200; // Ajustar según el motor (200 es común para 1.8°)
const int STEP_DELAY_US = 6000; // Velocidad del motor (menor = más rápido)

void setup() {
  Serial.begin(115200);
  Serial2.begin(9600, SERIAL_8N1, 16, 17); // RX=16, TX=17
  
  pinMode(PIN_ENABLE, OUTPUT);
  digitalWrite(PIN_ENABLE, HIGH); // Motores desactivados por defecto (Low active en A4988)

  for (int i = 0; i < 8; i++) {
    pinMode(motors[i].stepPin, OUTPUT);
    pinMode(motors[i].dirPin, OUTPUT);
    digitalWrite(motors[i].stepPin, LOW);
    digitalWrite(motors[i].dirPin, LOW);
  }

  Serial.println("--- ESCLAVO MOTORES INICIADO ---");
}

void girarMotor(int index) {
  if (index < 0 || index >= 8) return;

  Serial.printf("[MOTOR] Girando motor #%d con torque máximo...\n", index + 1);
  
  // 1. Activar drivers y esperar un momento para estabilizar corriente
  digitalWrite(PIN_ENABLE, LOW); 
  delay(50); // Aumentado para asegurar torque inicial

  // 2. Establecer dirección
  digitalWrite(motors[index].dirPin, HIGH);

  // 3. Dar una revolución completa (200 pasos)
  // Usamos un micro-delay un poco más alto para máxima fuerza
  for (int x = 0; x < STEPS_PER_REV; x++) {
    digitalWrite(motors[index].stepPin, HIGH);
    delayMicroseconds(STEP_DELAY_US);
    digitalWrite(motors[index].stepPin, LOW);
    delayMicroseconds(STEP_DELAY_US);
  }

  // 4. Mantener el motor bloqueado un instante para evitar que el resorte retroceda
  delay(200); 
  
  // 5. Desactivar drivers
  digitalWrite(PIN_ENABLE, HIGH); 
  Serial.println("[MOTOR] Giro completado.");
}

void loop() {
  if (Serial2.available()) {
    String cmd = Serial2.readStringUntil('\n');
    cmd.trim();
    
    if (cmd.length() == 0) return;

    Serial.printf("[COMM] Recibido: '%s'\n", cmd.c_str());

    if (cmd.startsWith("MOVE:")) {
      String code = cmd.substring(5);
      Serial.printf("[ACTION] Procesando MOVE para: %s\n", code.c_str());
      
      int motorIndex = -1;
      
      if (code == "1" || code == "A1") motorIndex = 0;
      else if (code == "2" || code == "A2") motorIndex = 1;
      else if (code == "3" || code == "A3") motorIndex = 2;
      else if (code == "4" || code == "A4") motorIndex = 3;
      else if (code == "5" || code == "B1") motorIndex = 4;
      else if (code == "6" || code == "B2") motorIndex = 5;
      else if (code == "7" || code == "B3") motorIndex = 6;
      else if (code == "8" || code == "B4") motorIndex = 7;

      if (motorIndex != -1) {
        Serial.printf("[MOTOR] Girando motor físico #%d\n", motorIndex + 1);
        girarMotor(motorIndex);
        Serial2.println("DONE");
        Serial.println("[COMM] OK: 'DONE' enviado al Maestro");
      } else {
        Serial.printf("[ERROR] Código '%s' no reconocido.\n", code.c_str());
      }
    } else {
      Serial.printf("[WARN] Comando desconocido: '%s'\n", cmd.c_str());
    }
  }
}
