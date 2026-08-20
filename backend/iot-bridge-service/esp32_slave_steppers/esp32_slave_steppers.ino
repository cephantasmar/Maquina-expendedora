/**
 * ESP32 SLAVE - CONTROL RIGUROSO DE MOTORES PAP (8 CANALES)
 * -------------------------------------------------------
 * Recibe comandos por Serial2 del ESP32 Maestro.
 * Optimizaciones: 
 *   - Gestión de calor activa (Enable/Disable por ciclo).
 *   - Mapeo de slots sincronizado con UI Maestro.
 *   - Torque máximo con retardos controlados.
 */

// ================= CONFIGURACIÓN DE HARDWARE =================
const int PIN_ENABLE = 4; // ENABLE común para todos los drivers (Activo en LOW)

struct Stepper {
  int stepPin;
  int dirPin;
};

// Mapeo físico de 8 motores (No cambiar pines a menos que cambie el cableado)
Stepper motors[8] = {
  {5,  18}, // Motor 1 -> Slot A1
  {19, 21}, // Motor 2 -> Slot A2
  {22, 23}, // Motor 3 -> Slot A3
  {25, 26}, // Motor 4 -> Slot A7
  {27, 32}, // Motor 5 -> Slot C1
  {33, 12}, // Motor 6 -> Slot C2
  {13, 14}, // Motor 7 -> Slot C3
  {2,  15}  // Motor 8 -> Slot C7
};

// Parámetros de movimiento
const int STEPS_PER_REV = 200;  // 1.8 grados por paso
const int STEP_DELAY_US = 3000; // Velocidad equilibrada para torque
const int START_DELAY_MS = 100; // Estabilización antes de giro
const int END_HOLD_MS = 200;    // Retención para evitar retroceso de resorte

void setup() {
  // Comunicación para depuración
  Serial.begin(115200);
  
  // Comunicación con Maestro (RX2=16, TX2=17)
  Serial2.begin(9600, SERIAL_8N1, 16, 17);
  
  delay(1000);
  Serial.println("--- ESCLAVO MOTORES INICIADO ---");

  // Configuración de pines
  pinMode(PIN_ENABLE, OUTPUT);
  digitalWrite(PIN_ENABLE, HIGH); // Iniciar DESHABILITADO (Frio)

  for (int i = 0; i < 8; i++) {
    pinMode(motors[i].stepPin, OUTPUT);
    pinMode(motors[i].dirPin, OUTPUT);
    digitalWrite(motors[i].stepPin, LOW);
    digitalWrite(motors[i].dirPin, LOW);
  }
}

/**
 * Ejecuta el giro físico de un motor específico
 */
void ejecutarGiro(int index, bool horario = true) {
  if (index < 0 || index >= 8) return;

  Serial.printf("[ACCION] Girando motor físico #%d (%s)\n", index + 1, horario ? "Horario" : "Anti-horario");
  
  // 1. Activar torque
  digitalWrite(PIN_ENABLE, LOW); 
  delay(START_DELAY_MS); 

  // 2. Establecer dirección
  digitalWrite(motors[index].dirPin, horario ? HIGH : LOW);

  // 3. Ciclo de pasos
  for (int x = 0; x < STEPS_PER_REV; x++) {
    digitalWrite(motors[index].stepPin, HIGH);
    delayMicroseconds(STEP_DELAY_US);
    digitalWrite(motors[index].stepPin, LOW);
    delayMicroseconds(STEP_DELAY_US);
  }

  delay(END_HOLD_MS); 
  
  // 5. Liberar torque para enfriar
  digitalWrite(PIN_ENABLE, HIGH); 
  Serial.println("[OK] Giro completado y motor liberado.");
}

void loop() {
  if (Serial2.available()) {
    String cmd = Serial2.readStringUntil('\n');
    cmd.trim();
    
    if (cmd.length() == 0) return;

    Serial.printf("[RX] Comando recibido: '%s'\n", cmd.c_str());

    if (cmd.startsWith("MOVE:")) {
      String code = cmd.substring(5);
      int motorIndex = -1;
      bool dir = true; 
      
      if      (code == "A1") { motorIndex = 0; dir = false; }
      else if (code == "A2") motorIndex = 1;
      else if (code == "A3") { motorIndex = 2; dir = false; } 
      else if (code == "A7") motorIndex = 3;
      else if (code == "C1") motorIndex = 4;
      else if (code == "C2") motorIndex = 5;
      else if (code == "C3") motorIndex = 6;
      else if (code == "C7") motorIndex = 7;

      if (motorIndex != -1) {
        ejecutarGiro(motorIndex, dir);
        Serial2.println("DONE"); 
        Serial.println("[TX] Notificación 'DONE' enviada.");
      } else {
        Serial.printf("[ERROR] Código de slot '%s' inválido.\n", code.c_str());
      }
    }
  }
}
