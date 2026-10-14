from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)

def test_health_endpoint():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}

def test_create_item():
    response = client.post("/items", json={"name": "keyboard", "quantity": 2})
    assert response.status_code == 200
    assert response.json()["item"] == {"name": "keyboard", "quantity": 2}

def test_create_item_rejects_invalid_quantity():
    response = client.post("/items", json={"name": "keyboard", "quantity": 0})
    assert response.status_code == 422
