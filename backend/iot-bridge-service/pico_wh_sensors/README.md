# Guía de Instalación en Raspberry Pi Pico WH

Para cargar el código en tu **Raspberry Pi Pico WH**:

1. Descarga e instala [Thonny IDE](https://thonny.org/).
2. Conecta tu Raspberry Pi Pico WH por cable USB mientras mantienes pulsado el botón **BOOTSEL**.
3. Instala el firmware de **MicroPython** en la Pico si aún no lo tiene (Thonny lo hace automáticamente desde `Herramientas > Opciones > Intérprete > Instalar MicroPython`).
4. Abre el archivo `pico_wh_sensors.py` en Thonny.
5. Guárdalo dentro de la Raspberry Pi Pico con el nombre **`main.py`** para que arranque de forma autónoma al encenderse la máquina.

### Cableado resumen:
- **UART al ESP32 Maestro**: `GP4` (TX) -> RX (GPIO 9 en ESP32), `GP5` (RX) -> TX (GPIO 10 en ESP32), `GND` común.
- **PN532 NFC (I2C)**: `GP6` (SDA), `GP7` (SCL), `3.3V`, `GND`.
- **HC-SR04**: `GP8` (TRIG), `GP9` (ECHO con divisor resistivo si usa 5V), `VCC`, `GND`.
- **DHT11**: `GP10` (DATA), `3.3V`, `GND`.
