
import logging
import os
from contextlib import asynccontextmanager
from typing import Generator

from fastapi import Depends, FastAPI, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import String, create_engine
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import (
    DeclarativeBase,
    Mapped,
    Session,
    mapped_column,
    sessionmaker,
)

# --------------------------------------------------
# Logging
# --------------------------------------------------

logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO").upper(),
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)

logger = logging.getLogger("orders-api")

# --------------------------------------------------
# Database configuration
# --------------------------------------------------

DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql+psycopg://orders_app:orders_local_password@db:5432/orders",
)


class Base(DeclarativeBase):
    pass


class Order(Base):
    __tablename__ = "orders"

    id: Mapped[int] = mapped_column(
        primary_key=True,
        autoincrement=True,
    )

    customer_name: Mapped[str] = mapped_column(
        String(120),
        nullable=False,
    )

    item: Mapped[str] = mapped_column(
        String(200),
        nullable=False,
    )

    quantity: Mapped[int] = mapped_column(
        nullable=False,
    )


engine = create_engine(
    DATABASE_URL,
    pool_pre_ping=True,
    pool_size=5,
    max_overflow=5,
)

SessionLocal = sessionmaker(
    bind=engine,
    expire_on_commit=False,
)

# --------------------------------------------------
# Request and response validation
# --------------------------------------------------


class OrderCreate(BaseModel):
    customer_name: str = Field(min_length=1, max_length=120)
    item: str = Field(min_length=1, max_length=200)
    quantity: int = Field(gt=0, le=10000)


class OrderResponse(BaseModel):
    id: int
    customer_name: str
    item: str
    quantity: int


# --------------------------------------------------
# Application lifecycle
# --------------------------------------------------


@asynccontextmanager
async def lifespan(app: FastAPI):
    try:
        # Suitable for this local assessment demo.
        # Use versioned database migrations in production.
        Base.metadata.create_all(bind=engine)
        logger.info("Database schema is ready")
    except SQLAlchemyError:
        logger.exception("Database initialization failed")
        raise

    yield

    engine.dispose()
    logger.info("Database engine disposed")


app = FastAPI(
    title="XYZZ Orders API",
    version="1.0.0",
    lifespan=lifespan,
)


# --------------------------------------------------
# Database session dependency
# --------------------------------------------------


def get_db() -> Generator[Session, None, None]:
    db = SessionLocal()

    try:
        yield db
    finally:
        db.close()


# --------------------------------------------------
# Health endpoint
# --------------------------------------------------


@app.get("/health")
def health():
    try:
        with engine.connect() as connection:
            connection.exec_driver_sql("SELECT 1")

        return {
            "status": "healthy",
            "database": "reachable",
        }

    except SQLAlchemyError:
        logger.exception("Database health check failed")

        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Database unavailable",
        )


# --------------------------------------------------
# Create order
# --------------------------------------------------


@app.post(
    "/orders",
    response_model=OrderResponse,
    status_code=status.HTTP_201_CREATED,
)
def create_order(
    payload: OrderCreate,
    db: Session = Depends(get_db),
):
    customer_name = payload.customer_name.strip()
    item_name = payload.item.strip()

    if not customer_name or not item_name:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Customer name and item cannot be blank",
        )

    order = Order(
        customer_name=customer_name,
        item=item_name,
        quantity=payload.quantity,
    )

    try:
        db.add(order)
        db.commit()
        db.refresh(order)

        logger.info("Order created: order_id=%s", order.id)

        return order

    except SQLAlchemyError:
        db.rollback()
        logger.exception("Failed to create order")

        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Unable to save order",
        )


# --------------------------------------------------
# Retrieve order
# --------------------------------------------------


@app.get(
    "/orders/{order_id}",
    response_model=OrderResponse,
)
def get_order(
    order_id: int,
    db: Session = Depends(get_db),
):
    try:
        order = db.get(Order, order_id)

    except SQLAlchemyError:
        logger.exception("Failed to retrieve order")

        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Unable to retrieve order",
        )

    if order is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Order not found",
        )

    return order
