import asyncio
import os
from typing import Any

from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware

from dashboard_schema import DashboardData
from vehicle_providers import (
    MockVehicleProvider,
    TeslaVehicleProvider,
    VehicleProvider,
    VehicleProviderNotImplementedError,
)


app = FastAPI(title="Tesla HUD Backend")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


def dashboard_to_json(data: DashboardData) -> dict[str, Any]:
    return data.model_dump()


def get_data_provider_name() -> str:
    return os.getenv("DATA_PROVIDER", "mock").strip().lower()


def get_vehicle_provider() -> VehicleProvider:
    provider_name = get_data_provider_name()

    if provider_name == "mock":
        return MockVehicleProvider()

    if provider_name == "tesla":
        return TeslaVehicleProvider()

    raise HTTPException(
        status_code=400,
        detail=f"Unsupported DATA_PROVIDER '{provider_name}'. Use 'mock' or 'tesla'.",
    )


def get_provider_dashboard_data(provider: VehicleProvider) -> dict[str, Any]:
    try:
        return dashboard_to_json(provider.get_dashboard_data())
    except VehicleProviderNotImplementedError as error:
        raise HTTPException(status_code=501, detail=str(error)) from error


def build_mock_vehicle_data() -> dict[str, Any]:
    return dashboard_to_json(MockVehicleProvider().get_dashboard_data())


@app.get("/")
async def health_check() -> dict[str, str]:
    return {"status": "ok", "service": "tesla-hud-backend"}


@app.get("/api/mock/vehicle")
async def get_mock_vehicle() -> dict[str, Any]:
    return build_mock_vehicle_data()


@app.get("/api/dashboard")
async def get_dashboard() -> dict[str, Any]:
    return get_provider_dashboard_data(get_vehicle_provider())


@app.websocket("/ws/vehicle")
async def vehicle_websocket(websocket: WebSocket) -> None:
    await websocket.accept()

    try:
        try:
            provider = get_vehicle_provider()
        except HTTPException as error:
            await websocket.send_json({"error": error.detail})
            await websocket.close(code=1011)
            return

        while True:
            try:
                await websocket.send_json(get_provider_dashboard_data(provider))
            except HTTPException as error:
                await websocket.send_json({"error": error.detail})
                await websocket.close(code=1011)
                return
            await asyncio.sleep(1)
    except WebSocketDisconnect:
        return
