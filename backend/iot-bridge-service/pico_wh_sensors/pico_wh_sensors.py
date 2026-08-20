"""
RASPBERRY PI PICO WH - SENSORES (NFC + ULTRASONIDO + TEMPERATURA)
-----------------------------------------------------------------
Tercer microcontrolador del sistema GROG Vending.

RESPONSABILIDADES:
  - Leer tarjetas NFC (PN532 por I2C) para autenticación/pago
  - Medir distancia con sensor ultrasónico HC-SR04 (detección de caída de producto)
  - Leer temperatura con sensor DHT11
  - Reportar todo al ESP32 Maestro por UART1

CONEXIONES:
  ── UART con ESP32 Maestro ──
    Pico WH  GP4 (TX1) ──► RX del ESP32 Maestro  (reemplaza al UART antiguo de sensores)
    Pico WH  GP5 (RX1) ◄── TX del ESP32 Maestro
    GND común

  ── PN532 NFC (I2C) ──
    Pico WH  GP6  (SDA / I2C1) ──► SDA del PN532
    Pico WH  GP7  (SCL / I2C1) ──► SCL del PN532
    3.3V y GND

  ── HC-SR04 (Ultrasonido) ──
    Pico WH  GP8  ──► TRIG
    Pico WH  GP9  ◄── ECHO  (¡usar divisor de voltaje 5V→3.3V si el HC-SR04 es de 5V!)

  ── DHT11 (Temperatura) ──
    Pico WH  GP10 ◄── DATA

PROTOCOLO UART con ESP32 Maestro (9600 baud, líneas terminadas en \\n):
  Pico WH → Maestro:
    NFC:<uid_hex>\\n          Ejemplo: NFC:04A3F21B\\n
    DIST:<cm_float>\\n        Ejemplo: DIST:15.3\\n
    TEMP:<celsius_float>\\n   Ejemplo: TEMP:24.5\\n
    PONG\\n                   Respuesta a PING del Maestro

  Maestro → Pico WH:
    PING\\n                   El Maestro verifica que el Pico sigue vivo
    MEDIR\\n                  Solicitar medida de distancia inmediata
    SCAN\\n                   Activar modo escaneo NFC
"""

from machine import Pin, I2C, UART
import utime
import dht

# ─────────────────────────────────────────────
# UART1: comunicación con ESP32 Maestro
# ─────────────────────────────────────────────
uart = UART(1, baudrate=9600, tx=Pin(4), rx=Pin(5))

# ─────────────────────────────────────────────
# DHT11 - Sensor de temperatura
# ─────────────────────────────────────────────
dht_sensor = dht.DHT11(Pin(10))

# ─────────────────────────────────────────────
# HC-SR04 - Sensor ultrasónico
# ─────────────────────────────────────────────
TRIG = Pin(8, Pin.OUT)
ECHO = Pin(9, Pin.IN)
TRIG.value(0)

# ─────────────────────────────────────────────
# PN532 NFC por I2C
# ─────────────────────────────────────────────
I2C_BUS    = I2C(1, sda=Pin(6), scl=Pin(7), freq=400000)
PN532_ADDR = 0x24  # Dirección I2C estándar del PN532

# ─────────────────────────────────────────────
# INTERVALOS
# ─────────────────────────────────────────────
TEMP_INTERVAL_MS = 5000   # Cada 5 segundos
DIST_INTERVAL_MS = 500    # Cada 500 ms (modo pasivo)
NFC_POLL_MS      = 300    # Cada 300 ms


# ══════════════════════════════════════════════
# FUNCIONES DE SENSORES
# ══════════════════════════════════════════════

def medir_distancia() -> float:
    """
    Mide distancia con HC-SR04.
    Devuelve distancia en cm, o -1.0 si hay error.
    """
    TRIG.value(0)
    utime.sleep_us(5)
    TRIG.value(1)
    utime.sleep_us(10)
    TRIG.value(0)

    # Esperar flanco de subida con timeout
    timeout_start = utime.ticks_us()
    while ECHO.value() == 0:
        if utime.ticks_diff(utime.ticks_us(), timeout_start) > 30000:
            return -1.0

    pulse_start = utime.ticks_us()

    # Esperar flanco de bajada con timeout
    while ECHO.value() == 1:
        if utime.ticks_diff(utime.ticks_us(), pulse_start) > 30000:
            return -1.0

    pulse_end = utime.ticks_us()
    duration  = utime.ticks_diff(pulse_end, pulse_start)
    cm        = (duration * 0.0343) / 2.0

    if cm < 1.0 or cm > 400.0:
        return -1.0
    return round(cm, 1)


def leer_temperatura() -> float:
    """
    Lee temperatura del DHT11.
    Devuelve temperatura en °C, o -99.0 si hay error.
    """
    try:
        dht_sensor.measure()
        return float(dht_sensor.temperature())
    except Exception as e:
        print(f"[DHT11] Error: {e}")
        return -99.0


# ──────────────────────────────────────────────
# PN532 - Funciones I2C básicas
# ──────────────────────────────────────────────

def pn532_wakeup():
    """Envía comando SAMConfiguration para despertar el PN532."""
    cmd = bytes([
        0x00, 0x00, 0xFF,        # Preámbulo
        0x03, 0xFD,              # Longitud y checksum de longitud
        0xD4, 0x14, 0x01,       # TFI + SAMConfiguration (modo normal)
        0x17, 0x00              # Checksum de datos + postámbulo
    ])
    try:
        I2C_BUS.writeto(PN532_ADDR, cmd)
        utime.sleep_ms(100)
        print("[NFC] PN532 despertado (SAMConfiguration OK)")
    except Exception as e:
        print(f"[NFC] Error al despertar PN532: {e}")


def pn532_read_uid() -> str | None:
    """
    Intenta leer el UID de una tarjeta NFC (ISO14443A).
    Devuelve el UID como string hexadecimal, o None si no hay tarjeta.
    """
    # Comando InListPassiveTarget: buscar 1 tarjeta ISO14443A
    cmd = bytes([
        0x00, 0x00, 0xFF,
        0x04, 0xFC,
        0xD4, 0x4A, 0x01, 0x00,  # InListPassiveTarget
        0xE1, 0x00
    ])
    try:
        I2C_BUS.writeto(PN532_ADDR, cmd)
        utime.sleep_ms(100)

        # Leer respuesta (hasta 20 bytes)
        response = I2C_BUS.readfrom(PN532_ADDR, 20)

        # Verificar respuesta válida: buscar 0xD5, 0x4B en la trama
        resp = list(response)
        try:
            idx = resp.index(0xD5)
            if resp[idx + 1] == 0x4B and resp[idx + 2] > 0:  # Al menos 1 tarjeta
                uid_len  = resp[idx + 6]
                uid_bytes = resp[idx + 7: idx + 7 + uid_len]
                uid_hex   = ''.join(f'{b:02X}' for b in uid_bytes)
                return uid_hex
        except (ValueError, IndexError):
            pass

    except Exception:
        pass

    return None


# ══════════════════════════════════════════════
# LOOP PRINCIPAL
# ══════════════════════════════════════════════

def main():
    print("─── PICO WH SENSORES INICIADO ───")
    print("Sensores: PN532 NFC | HC-SR04 | DHT11")
    print("Comunicación: UART1 → ESP32 Maestro (GP4/GP5, 9600 baud)")

    pn532_wakeup()

    last_temp = utime.ticks_ms()
    last_dist = utime.ticks_ms()
    last_nfc  = utime.ticks_ms()
    last_uid  = None   # Evitar enviar el mismo UID repetidamente
    uart_buf  = b""

    while True:
        now = utime.ticks_ms()

        # ── Escuchar comandos del Maestro ──────────────
        if uart.any():
            uart_buf += uart.read(uart.any())
            while b"\n" in uart_buf:
                line, uart_buf = uart_buf.split(b"\n", 1)
                cmd = line.decode("utf-8").strip()

                if cmd == "PING":
                    uart.write(b"PONG\n")
                    print("[UART] PING → PONG")

                elif cmd == "MEDIR":
                    d = medir_distancia()
                    if d > 0:
                        msg = f"DIST:{d}\n".encode()
                        uart.write(msg)
                        print(f"[UART] Medida urgente enviada: {d} cm")

                elif cmd == "SCAN":
                    uid = pn532_read_uid()
                    if uid:
                        uart.write(f"NFC:{uid}\n".encode())
                        print(f"[UART] NFC bajo demanda: {uid}")

        # ── Temperatura cada TEMP_INTERVAL_MS ──────────
        if utime.ticks_diff(now, last_temp) >= TEMP_INTERVAL_MS:
            last_temp = now
            temp = leer_temperatura()
            if temp != -99.0:
                uart.write(f"TEMP:{temp}\n".encode())
                print(f"[TEMP] {temp}°C → Maestro")

        # ── Distancia periódica cada DIST_INTERVAL_MS ──
        if utime.ticks_diff(now, last_dist) >= DIST_INTERVAL_MS:
            last_dist = now
            d = medir_distancia()
            if d > 0:
                uart.write(f"DIST:{d}\n".encode())
                # (silencioso a menos que sea debug, para no saturar)

        # ── NFC polling cada NFC_POLL_MS ───────────────
        if utime.ticks_diff(now, last_nfc) >= NFC_POLL_MS:
            last_nfc = now
            uid = pn532_read_uid()
            if uid and uid != last_uid:
                last_uid = uid
                uart.write(f"NFC:{uid}\n".encode())
                print(f"[NFC] Tarjeta detectada: {uid}")
            elif not uid:
                last_uid = None  # Resetear cuando se retira la tarjeta

        utime.sleep_ms(10)


if __name__ == "__main__":
    main()
