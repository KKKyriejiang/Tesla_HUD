from fastapi.testclient import TestClient

from main import app


client = TestClient(app)


def assert_dashboard_schema(data: dict) -> None:
    assert "timestamp" in data
    assert "speed_kmh" in data
    assert "gear" in data
    assert "battery_percent" in data
    assert "range_km" in data
    assert "media" in data

    media = data["media"]
    assert "title" in media
    assert "artist" in media
    assert "status" in media
    assert "source" in media


def assert_dashboard_values(data: dict) -> None:
    assert data["gear"] in {"P", "N", "D", "R"}
    assert isinstance(data["speed_kmh"], (int, float))
    assert 0 <= data["battery_percent"] <= 100
    assert isinstance(data["range_km"], (int, float))


def test_health_check() -> None:
    response = client.get("/")

    assert response.status_code == 200
    assert response.json() == {
        "status": "ok",
        "service": "tesla-hud-backend",
    }


def test_mock_vehicle_endpoint_returns_dashboard_data() -> None:
    response = client.get("/api/mock/vehicle")

    assert response.status_code == 200
    assert_dashboard_schema(response.json())


def test_mock_vehicle_data_types_and_ranges() -> None:
    response = client.get("/api/mock/vehicle")

    assert response.status_code == 200
    assert_dashboard_values(response.json())


def test_dashboard_endpoint_uses_mock_provider_by_default(monkeypatch) -> None:
    monkeypatch.delenv("DATA_PROVIDER", raising=False)

    response = client.get("/api/dashboard")

    assert response.status_code == 200
    data = response.json()
    assert_dashboard_schema(data)
    assert_dashboard_values(data)
    assert data["media"]["source"] == "mock"


def test_dashboard_endpoint_uses_mock_provider_when_configured(monkeypatch) -> None:
    monkeypatch.setenv("DATA_PROVIDER", "mock")

    response = client.get("/api/dashboard")

    assert response.status_code == 200
    data = response.json()
    assert_dashboard_schema(data)
    assert_dashboard_values(data)
    assert data["media"]["source"] == "mock"


def test_dashboard_endpoint_returns_clear_error_for_tesla_provider(monkeypatch) -> None:
    monkeypatch.setenv("DATA_PROVIDER", "tesla")

    response = client.get("/api/dashboard")

    assert response.status_code == 501
    assert response.json() == {"detail": "Tesla provider not implemented yet"}


def test_vehicle_websocket_streams_mock_dashboard_data(monkeypatch) -> None:
    monkeypatch.setenv("DATA_PROVIDER", "mock")

    with client.websocket_connect("/ws/vehicle") as websocket:
        first_message = websocket.receive_json()
        second_message = websocket.receive_json()

    assert_dashboard_schema(first_message)
    assert_dashboard_values(first_message)
    assert_dashboard_schema(second_message)
    assert_dashboard_values(second_message)
    assert second_message["timestamp"] >= first_message["timestamp"]
