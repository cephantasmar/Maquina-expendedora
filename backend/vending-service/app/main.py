import os
from datetime import datetime
from uuid import uuid4

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from sqlalchemy import DateTime, Float, Integer, String, create_engine
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, sessionmaker

DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./vending.db")

engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)


class Base(DeclarativeBase):
    pass


class Machine(Base):
    __tablename__ = "machines"
    id: Mapped[str] = mapped_column(String, primary_key=True)
    owner_email: Mapped[str] = mapped_column(String, index=True)
    name: Mapped[str] = mapped_column(String)
    latitude: Mapped[float] = mapped_column(Float)
    longitude: Mapped[float] = mapped_column(Float)
    status: Mapped[str] = mapped_column(String, default="online")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)


class Product(Base):
    __tablename__ = "products"
    id: Mapped[str] = mapped_column(String, primary_key=True)
    sku: Mapped[str] = mapped_column(String, unique=True)
    name: Mapped[str] = mapped_column(String)
    price: Mapped[float] = mapped_column(Float)


class Inventory(Base):
    __tablename__ = "inventory"
    id: Mapped[str] = mapped_column(String, primary_key=True)
    machine_id: Mapped[str] = mapped_column(String, index=True)
    product_id: Mapped[str] = mapped_column(String, index=True)
    slot: Mapped[str] = mapped_column(String)
    stock: Mapped[int] = mapped_column(Integer)
    capacity: Mapped[int] = mapped_column(Integer)
    price: Mapped[float] = mapped_column(Float, nullable=True)
    is_enabled: Mapped[bool] = mapped_column(Integer, default=1) # 1=True, 0=False para SQLite
    slot_type: Mapped[str] = mapped_column(String, default="soda") # "soda" o "snack"

class GlobalSetting(Base):
    __tablename__ = "global_settings"
    key: Mapped[str] = mapped_column(String, primary_key=True)
    value: Mapped[str] = mapped_column(Text) # Cambiado a Text para base64

Base.metadata.create_all(bind=engine)
app = FastAPI(title="Grog Vending Service")


def _seed() -> None:
    with SessionLocal() as db:
        if db.query(Machine).count() == 0:
            db.add_all(
                [
                    Machine(id="MACHINE-001", owner_email="admin@grog.com", name="Campus Norte", latitude=-17.8, longitude=-63.2, status="online"),
                    Machine(id="MACHINE-002", owner_email="admin@grog.com", name="Campus Sur", latitude=-17.81, longitude=-63.22, status="offline"),
                ]
            )
        if db.query(Product).count() == 0:
            db.add_all([
                Product(id="PROD-1", sku="SODA-001", name="Soda", price=8.5), 
                Product(id="PROD-2", sku="CHIPS-002", name="Chips", price=6.0),
                Product(id="PROD-NONE", sku="NONE", name="Vacío", price=0.0)
            ])
        
        if db.query(Inventory).count() == 0:
            # Asegurar 16 slots para MACHINE-001
            slots = []
            for row in ['A', 'B', 'C', 'D']:
                for col in range(1, 5):
                    slot_name = f"{row}{col}"
                    prod_id = "PROD-1" if row in ['A', 'B'] else "PROD-2"
                    stype = "soda" if row in ['A', 'B'] else "snack"
                    slots.append(Inventory(
                        id=str(uuid4()), 
                        machine_id="MACHINE-001", 
                        product_id=prod_id, 
                        slot=slot_name, 
                        stock=10, 
                        capacity=20, 
                        price=8.5 if stype=="soda" else 6.0,
                        is_enabled=True,
                        slot_type=stype
                    ))
            db.add_all(slots)
            
        if db.query(GlobalSetting).filter(GlobalSetting.key == "banner_url").count() == 0:
            db.add(GlobalSetting(key="banner_url", value="https://via.placeholder.com/400x100?text=Publicidad+Grog"))
            
        db.commit()


_seed()


class InventoryUpdateRequest(BaseModel):
    stock: int
    capacity: int

class SlotStatusRequest(BaseModel):
    is_enabled: bool
    slot_type: str | None = None

class BannerRequest(BaseModel):
    url: str


@app.get("/health")
def health() -> dict:
    return {"status": "ok", "service": "vending-service"}

@app.get("/api/v1/settings/banner")
def get_banner() -> dict:
    with SessionLocal() as db:
        setting = db.query(GlobalSetting).filter(GlobalSetting.key == "banner_url").first()
        return {"url": setting.value if setting else ""}

@app.post("/api/v1/admin/settings/banner")
def update_banner(req: BannerRequest) -> dict:
    with SessionLocal() as db:
        setting = db.query(GlobalSetting).filter(GlobalSetting.key == "banner_url").first()
        if not setting:
            setting = GlobalSetting(key="banner_url", value=req.url)
            db.add(setting)
        else:
            setting.value = req.url
        db.commit()
        return {"status": "updated", "url": req.url}

@app.get("/api/v1/machines")
def list_machines(owner_email: str | None = None) -> dict:
    with SessionLocal() as db:
        query = db.query(Machine)
        if owner_email:
            query = query.filter(Machine.owner_email == owner_email)
        machines = query.all()
        return {"machines": [{"id": m.id, "owner_email": m.owner_email, "name": m.name, "status": m.status, "lat": m.latitude, "lng": m.longitude} for m in machines]}


@app.get("/api/v1/machines/{machine_id}/inventory")
def machine_inventory(machine_id: str) -> dict:
    with SessionLocal() as db:
        rows = db.query(Inventory, Product).join(Product, Inventory.product_id == Product.id).filter(Inventory.machine_id == machine_id).all()
        return {
            "items": [
                {
                    "inventory_id": inv.id,
                    "slot": inv.slot,
                    "stock": inv.stock,
                    "capacity": inv.capacity,
                    "product_sku": prod.sku,
                    "product_name": prod.name,
                    "price": inv.price if inv.price is not None else prod.price,
                    "is_enabled": bool(inv.is_enabled),
                    "slot_type": inv.slot_type
                }
                for inv, prod in rows
            ]
        }


@app.get("/api/v1/machines/{machine_id}/slots/{slot_id}")
def get_slot_info(machine_id: str, slot_id: str) -> dict:
    with SessionLocal() as db:
        row = (
            db.query(Inventory, Product)
            .join(Product, Inventory.product_id == Product.id)
            .filter(Inventory.machine_id == machine_id, Inventory.slot == slot_id)
            .first()
        )
        if not row:
            raise HTTPException(status_code=404, detail="Slot not found")
        
        inv, prod = row
        return {
            "slot": inv.slot,
            "product_id": prod.id,
            "product_name": prod.name,
            "price": inv.price if inv.price is not None else prod.price,
            "stock": inv.stock,
            "is_enabled": bool(inv.is_enabled),
            "slot_type": inv.slot_type
        }


@app.patch("/api/v1/machines/{machine_id}/inventory/{slot_or_id}/status")
def update_slot_status(machine_id: str, slot_or_id: str, req: SlotStatusRequest) -> dict:
    with SessionLocal() as db:
        item = db.query(Inventory).filter(
            (Inventory.machine_id == machine_id) & 
            ((Inventory.id == slot_or_id) | (Inventory.slot == slot_or_id))
        ).first()
        
        if not item:
            raise HTTPException(status_code=404, detail="Inventory item not found")
            
        item.is_enabled = req.is_enabled
        if req.slot_type:
            item.slot_type = req.slot_type
        db.commit()
        return {"status": "updated", "slot": item.slot, "is_enabled": bool(item.is_enabled), "slot_type": item.slot_type}


@app.patch("/api/v1/machines/{machine_id}/inventory/{slot_or_id}/price")
def update_inventory_price(machine_id: str, slot_or_id: str, price: float) -> dict:
    with SessionLocal() as db:
        # Buscar por ID de inventario o por slot en esa máquina
        item = db.query(Inventory).filter(
            (Inventory.machine_id == machine_id) & 
            ((Inventory.id == slot_or_id) | (Inventory.slot == slot_or_id))
        ).first()
        
        if not item:
            raise HTTPException(status_code=404, detail="Inventory item not found")
            
        item.price = price
        db.commit()
        return {"status": "updated", "machine_id": machine_id, "slot": item.slot, "new_price": price}


@app.patch("/api/v1/products/{product_id}/price")
def update_product_price(product_id: str, price: float) -> dict:
    with SessionLocal() as db:
        # Intentar buscar por ID, si no existe, buscar por SKU
        product = db.query(Product).filter((Product.id == product_id) | (Product.sku == product_id)).first()
        if not product:
            raise HTTPException(status_code=404, detail="Product not found")
        product.price = price
        db.commit()
        return {"status": "updated", "product_id": product.id, "sku": product.sku, "new_price": price}


@app.patch("/api/v1/inventory/{inventory_id}")
def update_inventory(inventory_id: str, req: InventoryUpdateRequest) -> dict:
    with SessionLocal() as db:
        row = db.get(Inventory, inventory_id)
        if not row:
            raise HTTPException(status_code=404, detail="Inventory not found")
        row.stock = req.stock
        row.capacity = req.capacity
        db.commit()
        return {"status": "updated", "inventory_id": inventory_id}


@app.get("/api/v1/admin/sales")
def admin_sales() -> dict:
    return {
        "daily_total": 120.5,
        "weekly_total": 870.0,
        "monthly_total": 3410.3,
    }
