import asyncio
import time
from typing import Any

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware


app = FastAPI(title="Tesla HUD Backend")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


def build_mock_vehicle_data() -> dict[str, Any]:
    now = time.time()
    tick = int(now)
    speed_sequence = [72, 74, 77, 80, 82, 79, 76, 73, 70, 68, 71]
    speed_kmh = speed_sequence[tick % len(speed_sequence)]
    battery_percent = max(0, 84 - ((tick // 20) % 5))
    range_km = 386 - ((tick // 5) % 12)
    media_status = "playing" if tick % 12 < 9 else "paused"

    return {
        "timestamp": now,
        "speed_kmh": speed_kmh,
        "gear": "D",
        "battery_percent": battery_percent,
        "range_km": range_km,
        "media": {
            "title": "Mock Drive",
            "artist": "Tesla HUD",
            "status": media_status,
            "source": "mock",
        },
    }


@app.get("/")
async def health_check() -> dict[str, str]:
    return {"status": "ok", "service": "tesla-hud-backend"}


@app.get("/api/mock/vehicle")
async def get_mock_vehicle() -> dict[str, Any]:
    return build_mock_vehicle_data()


@app.websocket("/ws/vehicle")
async def vehicle_websocket(websocket: WebSocket) -> None:
    await websocket.accept()

    try:
        while True:
            await websocket.send_json(build_mock_vehicle_data())
            await asyncio.sleep(1)
    except WebSocketDisconnect:
        return
