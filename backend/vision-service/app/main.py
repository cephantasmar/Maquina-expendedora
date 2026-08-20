from fastapi import FastAPI, HTTPException, BackgroundTasks, Response
from pydantic import BaseModel
import cv2
import numpy as np
import requests
import time
import json
import asyncio
import threading
from typing import Optional

from fastapi.responses import HTMLResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles
from fastapi import Request # Import Request

# --- CONFIGURACIÓN ---
# Leer desde variables de entorno o archivo de configuración
VISION_CONFIG_FILE = "vision_config.json"
# URL base del Transaction Orchestrator Service
ORCHESTRATOR_URL = "http://orchestrator-service:8010/api/v1/transactions/{tx_id}/dispense-result"

# Parámetros de detección de movimiento (valores por defecto)
_roi = (0, 0, 0, 0)  # x, y, ancho, alto
_threshold = 25     # Sensibilidad de detección
_min_area = 5000    # Área mínima del contorno para considerar movimiento
_camera_url = ""    # URL del streaming del celular/webcam
_is_monitoring = False # Estado de monitoreo
_current_tx_id: Optional[str] = None # ID de la transacción actual
_monitoring_thread: Optional[threading.Thread] = None
_stop_event = threading.Event()

app = FastAPI(title="Grog Vision Service")

app.mount("/static", StaticFiles(directory="frontend"), name="static")

@app.get("/", response_class=HTMLResponse)
async def read_root(request: Request):
    with open("frontend/index.html", "r") as f:
        html_content = f.read()
    return HTMLResponse(content=html_content, status_code=200)

class VisionConfig(BaseModel):
    camera_url: str
    roi: tuple[int, int, int, int]
    threshold: int
    min_area: int

class StartMonitoringRequest(BaseModel):
    tx_id: str
    duration_seconds: int = 10 # Cuánto tiempo monitorear

class DispenseResultPayload(BaseModel):
    success: bool
    initial_distance: Optional[float] = None
    final_distance: Optional[float] = None
    error_log: Optional[str] = None

def _load_config():
    global _roi, _threshold, _min_area, _camera_url
    try:
        with open(VISION_CONFIG_FILE, 'r') as f:
            config = json.load(f)
            _camera_url = config.get("camera_url", "")
            _roi = tuple(config.get("roi", (0, 0, 0, 0)))
            _threshold = config.get("threshold", 25)
            _min_area = config.get("min_area", 5000)
        print("Configuración de visión cargada.")
    except FileNotFoundError:
        print("Archivo de configuración no encontrado. Usando valores por defecto.")
    except Exception as e:
        print(f"Error al cargar configuración: {e}. Usando valores por defecto.")

def _save_config():
    try:
        config = {
            "camera_url": _camera_url,
            "roi": _roi,
            "threshold": _threshold,
            "min_area": _min_area,
        }
        with open(VISION_CONFIG_FILE, 'w') as f:
            json.dump(config, f, indent=4)
        print("Configuración de visión guardada.")
    except Exception as e:
        print(f"Error al guardar configuración: {e}")

# Cargar configuración al iniciar el servicio
_load_config()


def _monitor_for_dispense(tx_id: str, duration_seconds: int, stop_event: threading.Event):
    global _is_monitoring, _current_tx_id
    _is_monitoring = True
    _current_tx_id = tx_id
    
    cap = None
    try:
        print(f"DEBUG: Monitoring started for TX {tx_id}. Attempting to open camera at: {_camera_url}")
        cap = cv2.VideoCapture(_camera_url)
        if not cap.isOpened():
            print(f"ERROR: Failed to open camera in _monitor_for_dispense for TX {tx_id} at URL: {_camera_url}")
            _notify_orchestrator(tx_id, False, f"Error: No se pudo abrir la cámara en {_camera_url} para monitoreo.")
            _is_monitoring = False
            _current_tx_id = None
            return

        ret, frame1 = cap.read()
        if not ret:
            print(f"ERROR: No se pudo leer el primer frame de la cámara para TX {tx_id}.")
            _notify_orchestrator(tx_id, False, "Error al leer frame inicial de la cámara del Vision Service.")
            _is_monitoring = False
            _current_tx_id = None
            return
        
        start_time = time.time()
        movement_detected = False

        while not stop_event.is_set() and (time.time() - start_time < duration_seconds):
            ret, frame2 = cap.read()
            if not ret:
                print("Advertencia: No se pudo leer un frame durante el monitoreo.")
                time.sleep(0.1) # Esperar un poco antes de reintentar
                continue

            x, y, w, h = _roi
            if w > 10 and h > 10 and y+h <= frame2.shape[0] and x+w <= frame2.shape[1]: # Asegurar que ROI es válido
                zona_interes = frame2[y:y+h, x:x+w]
                zona_ant = frame1[y:y+h, x:x+w]

                diff = cv2.absdiff(zona_interes, zona_ant)
                gray = cv2.cvtColor(diff, cv2.COLOR_BGR2GRAY)
                blur = cv2.GaussianBlur(gray, (5,5), 0)
                _, thresh = cv2.threshold(blur, _threshold, 255, cv2.THRESH_BINARY)
                
                # Opcional: dilate para unir pequeños contornos
                # dilated = cv2.dilate(thresh, None, iterations=2) 
                
                contours, _ = cv2.findContours(thresh, cv2.RETR_TREE, cv2.CHAIN_APPROX_SIMPLE)

                for contour in contours:
                    if cv2.contourArea(contour) > _min_area:
                        print(f"[{tx_id}] ¡Movimiento detectado por Visión Artificial! Área: {cv2.contourArea(contour)}")
                        movement_detected = True
                        break # Un movimiento es suficiente
                
                if movement_detected:
                    break # Salir del bucle si se detectó movimiento
            
            frame1 = frame2
            time.sleep(0.05) # Pequeña pausa para evitar 100% CPU

        if movement_detected:
            _notify_orchestrator(tx_id, True, "Confirmado por Visión Artificial (OpenCV)")
        else:
            _notify_orchestrator(tx_id, False, "No se detectó movimiento por Visión Artificial en el tiempo establecido.")

    except Exception as e:
        print(f"Error en el monitoreo de visión: {e}")
        _notify_orchestrator(tx_id, False, f"Error interno del Vision Service: {e}")
    finally:
        if cap:
            cap.release()
        _is_monitoring = False
        _current_tx_id = None
        print(f"Monitoreo para TX {tx_id} finalizado.")

def _notify_orchestrator(tx_id: str, success: bool, log_message: str):
    url = ORCHESTRATOR_URL.format(tx_id=tx_id)
    payload = DispenseResultPayload(success=success, error_log=log_message).model_dump_json()
    headers = {"Content-Type": "application/json"}
    
    try:
        response = requests.post(url, json=payload, headers=headers)
        if response.status_code == 200:
            print(f"Notificación exitosa al Orquestador para TX {tx_id}. Resultado: {success}")
        else:
            print(f"Error al notificar al Orquestador para TX {tx_id}. Status: {response.status_code}, Respuesta: {response.text}")
    except requests.exceptions.ConnectionError as e:
        print(f"Error de conexión al notificar al Orquestador para TX {tx_id}: {e}")
    except Exception as e:
        print(f"Error desconocido al notificar al Orquestador para TX {tx_id}: {e}")

# --- ENDPOINTS API ---

@app.get("/health")
def health() -> dict:
    return {"status": "ok", "service": "vision-service"}

@app.post("/api/v1/vision/config")
def update_vision_config(config: VisionConfig):
    global _roi, _threshold, _min_area, _camera_url
    if _is_monitoring:
        raise HTTPException(status_code=400, detail="No se puede cambiar la configuración mientras se está monitoreando.")
    
    _camera_url = config.camera_url
    _roi = config.roi
    _threshold = config.threshold
    _min_area = config.min_area
    _save_config()
    return {"status": "success", "message": "Configuración actualizada y guardada."}

@app.get("/api/v1/vision/config")
def get_vision_config() -> VisionConfig:
    return VisionConfig(
        camera_url=_camera_url,
        roi=_roi,
        threshold=_threshold,
        min_area=_min_area
    )

@app.post("/api/v1/vision/start-monitoring")
async def start_monitoring(request: StartMonitoringRequest, background_tasks: BackgroundTasks):
    global _is_monitoring, _monitoring_thread, _stop_event
    if _is_monitoring:
        raise HTTPException(status_code=400, detail="Ya se está monitoreando una transacción.")
    
    if not _camera_url:
        raise HTTPException(status_code=400, detail="URL de la cámara no configurada. Por favor, configure primero.")
    
    x, y, w, h = _roi
    if not (w > 0 and h > 0):
        raise HTTPException(status_code=400, detail="ROI no configurado o inválido. Por favor, configure primero.")

    _stop_event.clear() # Asegurarse de que el evento de parada esté limpio
    _monitoring_thread = threading.Thread(target=_monitor_for_dispense, args=(request.tx_id, request.duration_seconds, _stop_event))
    _monitoring_thread.start()
    
    return {"status": "monitoring_started", "tx_id": request.tx_id, "duration": request.duration_seconds}

@app.post("/api/v1/vision/stop-monitoring")
def stop_monitoring():
    global _is_monitoring, _monitoring_thread, _stop_event
    if not _is_monitoring:
        return {"status": "not_monitoring", "message": "No hay monitoreo activo para detener."}
    
    _stop_event.set() # Señalizar al hilo de monitoreo para que se detenga
    if _monitoring_thread and _monitoring_thread.is_alive():
        _monitoring_thread.join(timeout=5) # Esperar a que el hilo termine
        if _monitoring_thread.is_alive():
            print("Advertencia: El hilo de monitoreo no se detuvo después de 5 segundos.")

    _is_monitoring = False
    return {"status": "monitoring_stopped", "message": "Monitoreo detenido."}

@app.get("/api/v1/vision/status")
def get_monitoring_status():
    return {
        "is_monitoring": _is_monitoring,
        "current_tx_id": _current_tx_id,
        "camera_url_set": bool(_camera_url),
        "roi_set": (_roi[2] > 0 and _roi[3] > 0)
    }

@app.get("/api/v1/vision/video_feed")
async def video_feed():
    global _camera_url
    if not _camera_url:
        print("DEBUG: video_feed called but _camera_url is empty. Reloading config...")
        _load_config()
        
    if not _camera_url:
        print(f"DEBUG: video_feed called but _camera_url is still empty. ROI: {_roi}")
        raise HTTPException(status_code=400, detail="URL de la cámara no configurada.")
    
    print(f"DEBUG: Attempting to open camera stream for video_feed at: {_camera_url}")
    cap = cv2.VideoCapture(_camera_url)
    if not cap.isOpened():
        print(f"ERROR: Failed to open camera in video_feed at URL: {_camera_url}")
        raise HTTPException(status_code=500, detail=f"Error: No se pudo abrir la cámara en {_camera_url}. Verifique la URL y la accesibilidad desde el contenedor Docker.")

    async def generate():
        global _roi, _threshold, _min_area
        _, frame1 = cap.read()
        
        while True:
            ret, frame = cap.read()
            if not ret:
                print("DEBUG: video_feed - Failed to read frame. Stream might have ended.")
                break
            
            # Dibujar ROI y estado de monitoreo
            x, y, w, h = _roi
            if w > 10 and h > 10:
                cv2.rectangle(frame, (x, y), (x+w, y+h), (0, 255, 0), 2) # Verde para ROI
                if _is_monitoring:
                    cv2.putText(frame, f"MONITORING TX: {_current_tx_id}", (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 255), 2)
                else:
                    cv2.putText(frame, "READY", (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 0), 2)
            else:
                 cv2.putText(frame, "ROI NOT SET", (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 0, 255), 2)

            # Convertir el frame a JPEG
            ret, buffer = cv2.imencode('.jpg', frame)
            frame_bytes = buffer.tobytes()

            yield (b'--frame\r\n'
                   b'Content-Type: image/jpeg\r\n\r\n' + frame_bytes + b'\r\n')
            
            frame1 = frame # Actualizar frame anterior

    try:
        return StreamingResponse(generate(), media_type="multipart/x-mixed-replace; boundary=frame")
    finally:
        if cap:
            print(f"DEBUG: video_feed - Releasing camera resource for {_camera_url}")
            cap.release()

