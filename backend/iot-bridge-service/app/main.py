import os
import httpx
from datetime import datetime, timedelta
from uuid import uuid4

from fastapi import FastAPI
from pydantic import BaseModel
from sqlalchemy import DateTime, Float, String, Text, create_engine
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, sessionmaker

DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./iot.db")
MQTT_BROKER_URL = os.getenv("MQTT_BROKER_URL", "mqtt://127.0.0.1:1883")
NOTIFICATION_SERVICE_URL = os.getenv("NOTIFICATION_SERVICE_URL", "http://notification-service:8070")
DEVOPS_EMAIL = os.getenv("DEVOPS_EMAIL", "devops@grog.com")

engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)


class Base(DeclarativeBase):
    pass


class TelemetryLog(Base):
    __tablename__ = "telemetry_logs"
    id: Mapped[str] = mapped_column(String, primary_key=True)
    machine_id: Mapped[str] = mapped_column(String, index=True)
    temperature: Mapped[float] = mapped_column(Float)
    humidity: Mapped[float] = mapped_column(Float)
    motor_status: Mapped[str] = mapped_column(String)
    status: Mapped[str] = mapped_column(String)
    raw_payload: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)


Base.metadata.create_all(bind=engine)
app = FastAPI(title="Grog IoT Bridge Service")


class TelemetryIn(BaseModel):
    machine_id: str
    temperature: float
    humidity: float
    motor_status: str
    status: str


def _seed() -> None:
    with SessionLocal() as db:
        if db.query(TelemetryLog).count() == 0:
            db.add_all(
                [
                    TelemetryLog(
                        id=str(uuid4()),
                        machine_id="MACHINE-001",
                        temperature=24.2,
                        humidity=39.0,
                        motor_status="OK",
                        status="online",
                        raw_payload='{"heartbeat":true}',
                        created_at=datetime.utcnow(),
                    ),
                    TelemetryLog(
                        id=str(uuid4()),
                        machine_id="MACHINE-002",
                        temperature=31.6,
                        humidity=58.0,
                        motor_status="WARN",
                        status="offline",
                        raw_payload='{"heartbeat":false}',
                        created_at=datetime.utcnow() - timedelta(minutes=15),
                    ),
                ]
            )
            db.commit()


_seed()


@app.get("/health")
def health() -> dict:
    return {"status": "ok", "service": "iot-bridge-service", "mqtt_broker": MQTT_BROKER_URL}


@app.get("/api/v1/iot/topics")
def topics() -> dict:
    return {
        "publish": [
            "grog/v1/machines/{machine_id}/commands/dispense",
            "grog/v1/machines/{machine_id}/commands/homing",
            "grog/v1/machines/{machine_id}/commands/restart",
        ],
        "subscribe": [
            "grog/v1/machines/{machine_id}/heartbeat",
            "grog/v1/machines/{machine_id}/telemetry",
            "grog/v1/machines/{machine_id}/events/dispense-result",
            "grog/v1/machines/{machine_id}/errors",
        ],
    }


@app.post("/api/v1/iot/telemetry")
def ingest_telemetry(req: TelemetryIn) -> dict:
    with SessionLocal() as db:
        db.add(
            TelemetryLog(
                id=str(uuid4()),
                machine_id=req.machine_id,
                temperature=req.temperature,
                humidity=req.humidity,
                motor_status=req.motor_status,
                status=req.status,
                raw_payload=req.model_dump_json(),
            )
        )
        db.commit()

    # Alertas para DEVOPS
    alerts = []
    if req.temperature > 30.0:
        alerts.append({
            "title": "🔥 Alerta de Alta Temperatura",
            "summary": f"Sensor crítico en {req.machine_id}",
            "description": f"La temperatura en la máquina {req.machine_id} ha subido a {req.temperature}°C. Peligro de daño en productos refrigerados.",
            "type": "error"
        })
    
    if req.motor_status != "OK":
        alerts.append({
            "title": "⚙️ Fallo en Motor",
            "summary": f"Atasco detectado en {req.machine_id}",
            "description": f"Se ha detectado un estado de motor '{req.motor_status}' en la máquina {req.machine_id}. Requiere revisión física.",
            "type": "warning"
        })

    if alerts:
        try:
            with httpx.Client() as client:
                for alert in alerts:
                    client.post(
                        f"{NOTIFICATION_SERVICE_URL}/api/v1/notifications/send",
                        json={
                            "user_email": DEVOPS_EMAIL,
                            **alert
                        },
                        timeout=2.0
                    )
        except Exception as e:
            print(f"ERROR sending IoT notification: {e}")

    return {"status": "stored"}


@app.get("/api/v1/iot/machines")
def machine_statuses() -> dict:
    with SessionLocal() as db:
        rows = db.query(TelemetryLog).order_by(TelemetryLog.created_at.desc()).all()
        latest = {}
        for row in rows:
            if row.machine_id not in latest:
                latest[row.machine_id] = row
        return {
            "machines": [
                {
                    "machine_id": r.machine_id,
                    "status": r.status,
                    "last_seen": r.created_at.isoformat(),
                    "temperature": r.temperature,
                    "humidity": r.humidity,
                    "motor_status": r.motor_status,
                }
                for r in latest.values()
            ]
        }


@app.get("/api/v1/iot/telemetry/{machine_id}")
def telemetry(machine_id: str) -> dict:
    with SessionLocal() as db:
        rows = (
            db.query(TelemetryLog)
            .filter(TelemetryLog.machine_id == machine_id)
            .order_by(TelemetryLog.created_at.desc())
            .limit(100)
            .all()
        )
        return {
            "items": [
                {
                    "timestamp": r.created_at.isoformat(),
                    "temperature": r.temperature,
                    "humidity": r.humidity,
                    "status": r.status,
                    "motor_status": r.motor_status,
                }
                for r in rows
            ]
        }


@app.post("/api/v1/iot/commands/{machine_id}/{command}")
def command(machine_id: str, command: str) -> dict:
    return {"status": "queued", "machine_id": machine_id, "command": command, "mqtt_broker": MQTT_BROKER_URL}
