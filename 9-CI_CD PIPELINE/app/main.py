from fastapi import FastAPI
from pydantic import BaseModel, Field

app = FastAPI(title="CI/CD Demo API", version="1.0.0")

class Item(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    quantity: int = Field(ge=1, le=1000)

@app.get("/health")
def health():
    return {"status": "ok"}

@app.post("/items")
def create_item(item: Item):
    return {"message": "item accepted", "item": item.model_dump()}
