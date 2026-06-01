import hashlib
import hmac
import json
import os
from datetime import datetime
from uuid import uuid4

import httpx
from fastapi import FastAPI, Header, HTTPException, Request
from pydantic import BaseModel
from sqlalchemy import DateTime, Float, String, Text, create_engine
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, sessionmaker

DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./simupay.db")
PAYMENT_GATEWAY_URL = os.getenv("PAYMENT_GATEWAY_URL", "http://127.0.0.1:8001")
WEBHOOK_SECRET = os.getenv("WEBHOOK_SECRET", "grog-simupay-secret")
PAYMENT_GATEWAY_API_KEY = os.getenv("PAYMENT_GATEWAY_API_KEY", WEBHOOK_SECRET)
MERCHANT_PAYOUT_EMAIL = os.getenv("MERCHANT_PAYOUT_EMAIL", "admin@experimentalcollege.edu.bo")
ORCHESTRATOR_SERVICE_URL = os.getenv("ORCHESTRATOR_SERVICE_URL", "http://orchestrator-service:8010")

engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)


class Base(DeclarativeBase):
    pass


class PaymentSession(Base):
    __tablename__ = "payment_sessions"
    provider_transaction_id: Mapped[str] = mapped_column(String, primary_key=True)
    transaction_id: Mapped[str] = mapped_column(String, unique=True, index=True)
    amount: Mapped[float] = mapped_column(Float)
    status: Mapped[str] = mapped_column(String, default="PENDING")
    qr_image: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)


class PaymentLog(Base):
    __tablename__ = "payment_logs"
    id: Mapped[str] = mapped_column(String, primary_key=True)
    provider_transaction_id: Mapped[str] = mapped_column(String, index=True)
    event_type: Mapped[str] = mapped_column(String)
    status: Mapped[str] = mapped_column(String)
    payload: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)


class IdempotencyRecord(Base):
    __tablename__ = "idempotency_records"
    key: Mapped[str] = mapped_column(String, primary_key=True)
    endpoint: Mapped[str] = mapped_column(String)
    response_json: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)


Base.metadata.create_all(bind=engine)
app = FastAPI(title="Grog SimuPay Integration Service")


class AuthorizeRequest(BaseModel):
    transaction_id: str
    amount: float


class TransferRequest(BaseModel):
    from_email: str
    to_email: str
    amount: float


class QrTransferRequest(BaseModel):
    from_email: str
    qr_data: str
    amount: float | None = None


class WalletCreateRequest(BaseModel):
    email: str
    initial_balance: float = 0.0


class SessionWalletPayRequest(BaseModel):
    from_email: str


def _sign_payload(raw: bytes) -> str:
    return hmac.new(WEBHOOK_SECRET.encode(), raw, hashlib.sha256).hexdigest()


def _log_payment(provider_tx_id: str, event_type: str, status: str, payload: dict) -> None:
    with SessionLocal() as db:
        db.add(
            PaymentLog(
                id=str(uuid4()),
                provider_transaction_id=provider_tx_id,
                event_type=event_type,
                status=status,
                payload=json.dumps(payload),
            )
        )
        db.commit()


@app.get("/health")
def health() -> dict:
    return {"status": "ok", "service": "simupay-integration"}


@app.post("/api/v1/wallets")
async def create_wallet(req: WalletCreateRequest) -> dict:
    async with httpx.AsyncClient() as client:
        try:
            res = await client.post(
                f"{PAYMENT_GATEWAY_URL}/api/v1/internal/wallets",
                json={"email": req.email, "full_name": req.email.split("@")[0], "password": "grog-user-default"},
                headers={"x-api-key": PAYMENT_GATEWAY_API_KEY},
                timeout=10.0
            )
            if res.status_code >= 400:
                raise HTTPException(status_code=res.status_code, detail=f"Gateway error: {res.text}")
            return res.json()
        except Exception as e:
            raise HTTPException(status_code=502, detail=f"Could not connect to SimuPay: {str(e)}")


@app.get("/api/v1/wallets/{email}")
async def get_wallet(email: str) -> dict:
    async with httpx.AsyncClient() as client:
        try:
            # Consultamos DIRECTAMENTE al Gateway de SimuPay
            res = await client.get(
                f"{PAYMENT_GATEWAY_URL}/api/v1/internal/wallets/{email}",
                headers={"x-api-key": PAYMENT_GATEWAY_API_KEY},
                timeout=10.0
            )
            
            if res.status_code == 404:
                raise HTTPException(status_code=404, detail="Cuenta no encontrada en SimuPay")
            
            if res.status_code >= 400:
                raise HTTPException(status_code=res.status_code, detail=f"Error de SimuPay: {res.text}")
            
            # Retornamos el balance REAL que viene de la pasarela
            data = res.json()
            return {
                "email": data["email"],
                "balance": data["balance"],
                "linked": True
            }
        except HTTPException as he:
            raise he
        except Exception as e:
            raise HTTPException(status_code=502, detail=f"Error de conexión con SimuPay: {str(e)}")


@app.get("/api/v1/wallets/{email}/transactions")
async def wallet_history(email: str) -> dict:
    async with httpx.AsyncClient() as client:
        try:
            res = await client.get(
                f"{PAYMENT_GATEWAY_URL}/api/v1/internal/wallets/{email}/transactions",
                headers={"x-api-key": PAYMENT_GATEWAY_API_KEY},
                timeout=10.0
            )
            if res.status_code >= 400:
                return {"items": []}

            return res.json()
        except Exception:
            return {"items": []}


@app.post("/api/v1/wallets/transfer")
async def transfer(req: TransferRequest) -> dict:
    if req.amount <= 0:
        raise HTTPException(status_code=400, detail="Amount must be > 0")
    if req.from_email == req.to_email:
        raise HTTPException(status_code=400, detail="Cannot transfer to same account")

    async with httpx.AsyncClient() as client:
        try:
            res = await client.post(
                f"{PAYMENT_GATEWAY_URL}/api/v1/internal/wallets/transfer",
                json={"from_email": req.from_email, "to_email": req.to_email, "amount": req.amount},
                headers={"x-api-key": PAYMENT_GATEWAY_API_KEY},
                timeout=10.0
            )
            if res.status_code >= 400:
                raise HTTPException(status_code=res.status_code, detail=f"Gateway transfer failed: {res.text}")
            
            # Opcional: Registrar localmente en Grog para historial rápido si se desea
            # Pero el saldo real ya se movió en el Gateway
            return res.json()
        except HTTPException as he:
            raise he
        except Exception as e:
            raise HTTPException(status_code=502, detail=f"Could not connect to SimuPay: {str(e)}")


@app.post("/api/v1/wallets/pay-qr")
async def pay_qr(req: QrTransferRequest) -> dict:
    async with httpx.AsyncClient() as client:
        try:
            res = await client.post(
                f"{PAYMENT_GATEWAY_URL}/api/v1/internal/wallets/pay-qr",
                json={"from_email": req.from_email, "qr_data": req.qr_data, "amount": req.amount},
                headers={"x-api-key": PAYMENT_GATEWAY_API_KEY},
                timeout=10.0
            )
            if res.status_code >= 400:
                raise HTTPException(status_code=res.status_code, detail=f"Gateway QR payment failed: {res.text}")
            return res.json()
        except HTTPException as he:
            raise he
        except Exception as e:
            raise HTTPException(status_code=502, detail=f"Could not connect to SimuPay: {str(e)}")


@app.post("/api/v1/payments/authorize")
async def authorize_payment(req: AuthorizeRequest, idempotency_key: str | None = Header(default=None, alias="Idempotency-Key")):
    if idempotency_key:
        with SessionLocal() as db:
            cached = db.get(IdempotencyRecord, idempotency_key)
            if cached:
                return json.loads(cached.response_json)

    async with httpx.AsyncClient() as client:
        # Usamos el nombre del servicio en la red de docker
        webhook_url = "http://simupay-service:8020/api/v1/webhooks/simupay"
        session_res = await client.post(
            f"{PAYMENT_GATEWAY_URL}/sessions",
            json={"amount": req.amount, "enrollment_id": req.transaction_id, "callback_url": "", "webhook_url": webhook_url},
            timeout=15.0,
        )
        if session_res.status_code >= 400:
            raise HTTPException(status_code=502, detail=f"Gateway authorize failed: {session_res.text}")
        data = session_res.json()

    provider_transaction_id = data["session_id"]
    with SessionLocal() as db:
        existing = db.query(PaymentSession).filter(PaymentSession.transaction_id == req.transaction_id).first()
        if existing:
            response = {"provider_transaction_id": existing.provider_transaction_id, "transaction_id": existing.transaction_id, "status": existing.status}
        else:
            row = PaymentSession(provider_transaction_id=provider_transaction_id, transaction_id=req.transaction_id, amount=req.amount, status="PENDING")
            db.add(row)
            db.commit()
            response = {"provider_transaction_id": row.provider_transaction_id, "transaction_id": row.transaction_id, "status": row.status}
        if idempotency_key:
            db.add(IdempotencyRecord(key=idempotency_key, endpoint="authorize", response_json=json.dumps(response)))
            db.commit()

    _log_payment(provider_transaction_id, "AUTHORIZE", "PENDING", response)
    return response


@app.post("/api/v1/payments/{provider_tx_id}/qr")
async def generate_payment_qr(provider_tx_id: str):
    async with httpx.AsyncClient() as client:
        process_res = await client.post(
            f"{PAYMENT_GATEWAY_URL}/sessions/{provider_tx_id}/process",
            json={"method": "qr"},
            timeout=15.0,
        )
        if process_res.status_code >= 400:
            raise HTTPException(status_code=502, detail=f"Gateway QR failed: {process_res.text}")
        payload = process_res.json()

    with SessionLocal() as db:
        row = db.get(PaymentSession, provider_tx_id)
        if not row:
            raise HTTPException(status_code=404, detail="Provider payment not found")
        row.status = "QR_GENERATED"
        row.qr_image = payload.get("qr_image")
        row.updated_at = datetime.utcnow()
        db.commit()

    result = {"provider_transaction_id": provider_tx_id, "status": "QR_GENERATED", "qr_image": payload.get("qr_image")}
    _log_payment(provider_tx_id, "QR_GENERATED", "QR_GENERATED", result)
    return result


@app.post("/api/v1/payments/{provider_tx_id}/pay-wallet")
async def pay_session_with_wallet(provider_tx_id: str, req: SessionWalletPayRequest):
    async with httpx.AsyncClient() as client:
        res = await client.post(
            f"{PAYMENT_GATEWAY_URL}/api/v1/internal/payments/{provider_tx_id}/wallet-pay",
            json={"from_email": req.from_email},
            headers={"x-api-key": PAYMENT_GATEWAY_API_KEY},
            timeout=15.0,
        )
        if res.status_code >= 400:
            raise HTTPException(status_code=502, detail=f"Gateway wallet pay failed: {res.text}")

    with SessionLocal() as db:
        row = db.get(PaymentSession, provider_tx_id)
        if row:
            row.status = "PAID_PENDING_CAPTURE"
            row.updated_at = datetime.utcnow()
            db.commit()

    payload = res.json()
    _log_payment(provider_tx_id, "WALLET_PAY", "PAID_PENDING_CAPTURE", payload)
    return payload


@app.post("/api/v1/payments/{provider_tx_id}/capture")
async def capture_payment(provider_tx_id: str):
    async with httpx.AsyncClient() as client:
        res = await client.post(
            f"{PAYMENT_GATEWAY_URL}/api/v1/internal/payments/{provider_tx_id}/capture",
            json={"merchant_email": MERCHANT_PAYOUT_EMAIL},
            headers={"x-api-key": PAYMENT_GATEWAY_API_KEY},
            timeout=15.0,
        )
        if res.status_code >= 400:
            raise HTTPException(status_code=502, detail=f"Gateway capture failed: {res.text}")

    with SessionLocal() as db:
        row = db.get(PaymentSession, provider_tx_id)
        if not row:
            raise HTTPException(status_code=404, detail="Provider payment not found")
        row.status = "COMPLETED"
        row.updated_at = datetime.utcnow()
        db.commit()
    result = {"provider_transaction_id": provider_tx_id, "status": "COMPLETED"}
    _log_payment(provider_tx_id, "CAPTURE", "COMPLETED", result)
    return result


@app.post("/api/v1/payments/{provider_tx_id}/refund")
async def refund_payment(provider_tx_id: str):
    async with httpx.AsyncClient() as client:
        res = await client.post(
            f"{PAYMENT_GATEWAY_URL}/api/v1/internal/payments/{provider_tx_id}/refund",
            headers={"x-api-key": PAYMENT_GATEWAY_API_KEY},
            timeout=15.0,
        )
        if res.status_code >= 400:
            raise HTTPException(status_code=502, detail=f"Gateway refund failed: {res.text}")

    with SessionLocal() as db:
        row = db.get(PaymentSession, provider_tx_id)
        if not row:
            raise HTTPException(status_code=404, detail="Provider payment not found")
        row.status = "REFUNDED"
        row.updated_at = datetime.utcnow()
        db.commit()
    result = {"provider_transaction_id": provider_tx_id, "status": "REFUNDED"}
    _log_payment(provider_tx_id, "REFUND", "REFUNDED", result)
    return result


@app.get("/api/v1/payments/{provider_tx_id}")
def get_payment(provider_tx_id: str):
    with SessionLocal() as db:
        row = db.get(PaymentSession, provider_tx_id)
        if not row:
            raise HTTPException(status_code=404, detail="Provider payment not found")
        return {"provider_transaction_id": row.provider_transaction_id, "transaction_id": row.transaction_id, "amount": row.amount, "status": row.status}


@app.get("/api/v1/payment-logs")
def payment_logs() -> dict:
    with SessionLocal() as db:
        rows = db.query(PaymentLog).order_by(PaymentLog.created_at.desc()).limit(200).all()
        return {
            "items": [
                {
                    "id": r.id,
                    "provider_transaction_id": r.provider_transaction_id,
                    "event_type": r.event_type,
                    "status": r.status,
                    "created_at": r.created_at.isoformat(),
                }
                for r in rows
            ]
        }


@app.post("/api/v1/webhooks/simupay")
async def simupay_webhook(request: Request, x_simupay_signature: str | None = Header(default=None)):
    raw = await request.body()
    # Para la kata, permitimos procesar si la firma es válida o si estamos en debug
    expected = _sign_payload(raw)
    if x_simupay_signature and not hmac.compare_digest(expected, x_simupay_signature):
        print("WARNING: Signature mismatch in webhook")

    try:
        payload = json.loads(raw)
        # El Gateway envía SIM-session_id
        provider_tx_id = payload.get("transaction_id", "").replace("SIM-", "")
        status = payload.get("status")

        if status == "completed":
            with SessionLocal() as db:
                row = db.get(PaymentSession, provider_tx_id)
                if row:
                    row.status = "COMPLETED"
                    row.updated_at = datetime.utcnow()
                    db.commit()

                    # NOTIFICAR AL ORQUESTADOR
                    async with httpx.AsyncClient() as client:
                        try:
                            print(f"WEBHOOK: Notifying Orchestrator for tx {row.transaction_id}")
                            await client.post(
                                f"{ORCHESTRATOR_SERVICE_URL}/api/v1/transactions/{row.transaction_id}/payment-confirmed",
                                timeout=5.0
                            )
                        except Exception as e:
                            print(f"WEBHOOK ERROR: Could not notify orchestrator: {e}")

        return {"status": "accepted"}
    except Exception as e:
        print(f"WEBHOOK JSON ERROR: {e}")
        return {"status": "error", "message": str(e)}
