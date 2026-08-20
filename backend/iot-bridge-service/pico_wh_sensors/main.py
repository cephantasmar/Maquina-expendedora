"""
RASPBERRY PI PICO WH - SENSORES (NFC + ULTRASONIDO + TEMPERATURA)
-----------------------------------------------------------------
Tercer microcontrolador del sistema GROG Vending.

RESPONSABILIDADES:
  - Leer tarjetas NFC (PN532 por I2C) para autenticación/pago
  - Medir distancia con sensor ultrasónico HC-SR04 (detección de caída de producto)
  - Leer temperatura con sensor DHT11
  - Reportar todo al ESP32 Maestro por UART1
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
# INTERVALOS DE LECTURA
# ─────────────────────────────────────────────
TEMP_INTERVAL_MS = 5000   # Cada 5 segundos
DIST_INTERVAL_MS = 500    # Cada 500 ms (modo pasivo)
NFC_POLL_MS      = 300    # Cada 300 ms


def medir_distancia() -> float:
    """Mide distancia con HC-SR04 en cm."""
    TRIG.value(0)
    utime.sleep_us(5)
    TRIG.value(1)
    utime.sleep_us(10)
    TRIG.value(0)

    # Esperar flanco de subida
    timeout_start = utime.ticks_us()
    while ECHO.value() == 0:
        if utime.ticks_diff(utime.ticks_us(), timeout_start) > 30000:
            return -1.0

    pulse_start = utime.ticks_us()

    # Esperar flanco de bajada
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
    """Lee temperatura del DHT11 en °C."""
    try:
        dht_sensor.measure()
        return float(dht_sensor.temperature())
    except Exception as e:
        print(f"[DHT11] Error: {e}")
        return -99.0


def pn532_wakeup():
    """Envía comando SAMConfiguration para despertar el módulo PN532."""
    cmd = bytes([
        0x00, 0x00, 0xFF,
        0x03, 0xFD,
        0xD4, 0x14, 0x01,
        0x17, 0x00
    ])
    try:
        I2C_BUS.writeto(PN532_ADDR, cmd)
        utime.sleep_ms(100)
        print("[NFC] PN532 despierto y listo.")
    except Exception as e:
        print(f"[NFC] Error iniciando PN532: {e}")


def pn532_read_uid() -> str | None:
    """Busca tarjetas NFC y retorna su UID hexadecimal."""
    cmd = bytes([
        0x00, 0x00, 0xFF,
        0x04, 0xFC,
        0xD4, 0x4A, 0x01, 0x00,
        0xE1, 0x00
    ])
    try:
        I2C_BUS.writeto(PN532_ADDR, cmd)
        utime.sleep_ms(100)
        response = I2C_BUS.readfrom(PN532_ADDR, 20)
        resp = list(response)
        
        try:
            idx = resp.index(0xD5)
            if resp[idx + 1] == 0x4B and resp[idx + 2] > 0:
                uid_len  = resp[idx + 6]
                uid_bytes = resp[idx + 7: idx + 7 + uid_len]
                return ''.join(f'{b:02X}' for b in uid_bytes)
        except (ValueError, IndexError):
            pass
    except Exception:
        pass
    return None


def main():
    print("─── PICO WH SENSORES INICIADO ───")
    pn532_wakeup()

    last_temp = utime.ticks_ms()
    last_dist = utime.ticks_ms()
    last_nfc  = utime.ticks_ms()
    last_uid  = None
    uart_buf  = b""

    while True:
        now = utime.ticks_ms()

        # 1. Escuchar peticiones del ESP32 Maestro
        if uart.any():
            uart_buf += uart.read(uart.any())
            while b"\n" in uart_buf:
                line, uart_buf = uart_buf.split(b"\n", 1)
                cmd = line.decode("utf-8").strip()

                if cmd == "PING":
                    uart.write(b"PONG\n")
                elif cmd == "MEDIR":
                    d = medir_distancia()
                    if d > 0:
                        uart.write(f"DIST:{d}\n".encode())
                elif cmd == "SCAN":
                    uid = pn532_read_uid()
                    if uid:
                        uart.write(f"NFC:{uid}\n".encode())

        # 2. Lectura y reporte de temperatura periódico
        if utime.ticks_diff(now, last_temp) >= TEMP_INTERVAL_MS:
            last_temp = now
            t = leer_temperatura()
            if t != -99.0:
                uart.write(f"TEMP:{t}\n".encode())

        # 3. Lectura periódica de distancia
        if utime.ticks_diff(now, last_dist) >= DIST_INTERVAL_MS:
            last_dist = now
            d = medir_distancia()
            if d > 0:
                uart.write(f"DIST:{d}\n".encode())

        # 4. Polling continuo de tarjetas NFC
        if utime.ticks_diff(now, last_nfc) >= NFC_POLL_MS:
            last_nfc = now
            uid = pn532_read_uid()
            if uid and uid != last_uid:
                last_uid = uid
                uart.write(f"NFC:{uid}\n".encode())
                print(f"[NFC] UID Detectado: {uid}")
            elif not uid:
                last_uid = None

        utime.sleep_ms(10)


if __name__ == "__main__":
    main()
