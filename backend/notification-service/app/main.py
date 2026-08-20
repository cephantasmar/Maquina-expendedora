import json
import asyncio
from typing import List, Dict
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException
from pydantic import BaseModel
from datetime import datetime
import uuid

app = FastAPI(title="Grog Notification Service")

# --- Models ---
class Notification(BaseModel):
    id: str
    user_email: str
    title: str
    summary: str
    description: str
    type: str # 'info', 'success', 'warning', 'error'
    is_read: bool
    created_at: str

class NotificationCreate(BaseModel):
    user_email: str
    title: str
    summary: str
    description: str
    type: str = "info"

# --- In-Memory Storage (In a real app, use a DB) ---
notifications_db: List[Dict] = []

# --- WebSocket Manager ---
class ConnectionManager:
    def __init__(self):
        self.active_connections: Dict[str, List[WebSocket]] = {}

    async def connect(self, websocket: WebSocket, user_email: str):
        await websocket.accept()
        if user_email not in self.active_connections:
            self.active_connections[user_email] = []
        self.active_connections[user_email].append(websocket)

    def disconnect(self, websocket: WebSocket, user_email: str):
        if user_email in self.active_connections:
            self.active_connections[user_email].remove(websocket)
            if not self.active_connections[user_email]:
                del self.active_connections[user_email]

    async def send_personal_message(self, message: dict, user_email: str):
        if user_email in self.active_connections:
            for connection in self.active_connections[user_email]:
                await connection.send_json(message)

manager = ConnectionManager()

# --- Endpoints ---

@app.get("/api/v1/notifications/{user_email}")
async def get_notifications(user_email: str):
    user_notifications = [n for n in notifications_db if n["user_email"] == user_email]
    return sorted(user_notifications, key=lambda x: x["created_at"], reverse=True)

@app.post("/api/v1/notifications/send")
async def create_notification(notif: NotificationCreate):
    new_notif = {
        "id": str(uuid.uuid4()),
        "user_email": notif.user_email,
        "title": notif.title,
        "summary": notif.summary,
        "description": notif.description,
        "type": notif.type,
        "is_read": False,
        "created_at": datetime.now().isoformat()
    }
    notifications_db.append(new_notif)
    
    # Send via WebSocket if user is online
    await manager.send_personal_message(new_notif, notif.user_email)
    
    return new_notif

@app.patch("/api/v1/notifications/{notification_id}/read")
async def mark_as_read(notification_id: str):
    for n in notifications_db:
        if n["id"] == notification_id:
            n["is_read"] = True
            return n
    raise HTTPException(status_code=404, detail="Notification not found")

@app.websocket("/ws/notifications/{user_email}")
async def websocket_endpoint(websocket: WebSocket, user_email: str):
    await manager.connect(websocket, user_email)
    try:
        while True:
            # Keep connection alive
            await websocket.receive_text()
    except WebSocketDisconnect:
        manager.disconnect(websocket, user_email)
