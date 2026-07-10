# Tesla HUD

Tesla HUD is a mobile auxiliary dashboard for Tesla owners. The project will provide a mock-first dashboard that can display vehicle speed, gear, battery level, range, and media information.

This app is not a replacement for Tesla's official vehicle display and must not implement safety-critical driving logic.

## Project Structure

```text
backend/
  .env.example
  main.py
  requirements.txt
mobile/
docs/
AGENTS.md
README.md
.gitignore
```

## Tech Stack

- Backend: Python FastAPI
- Frontend: Flutter
- Communication: WebSocket
- Development mode: mock data first
- Future integration: Tesla Fleet API and Fleet Telemetry

## Local Development Plan

1. Define the shared dashboard data schema used by mock and future real data.
2. Build the FastAPI backend with mock WebSocket data.
3. Build the Flutter mobile app shell once Flutter is available in the environment.
4. Connect the mobile app to the backend WebSocket in mock mode.
5. Add tests around schema stability and WebSocket message handling.
6. Document any new setup steps as they are introduced.

## Current Status

This repository currently contains the initial monorepo structure and a mock-first FastAPI backend. Tesla API integration has not been implemented.

## Backend Development on Windows

From PowerShell:

```powershell
cd backend
py -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

Health check:

```text
http://127.0.0.1:8000
```

Mock vehicle dashboard data:

```text
http://127.0.0.1:8000/api/mock/vehicle
```

Mock vehicle WebSocket:

```text
ws://127.0.0.1:8000/ws/vehicle
```

## Mobile Development

The Flutter app lives in `mobile/tesla_hud_app` and connects to the backend WebSocket.

From PowerShell:

```powershell
cd mobile\tesla_hud_app
flutter run
```

The default WebSocket URL is:

```text
ws://127.0.0.1:8000/ws/vehicle
```

Override it with `--dart-define` when needed:

```powershell
flutter run --dart-define=WS_URL=ws://127.0.0.1:8000/ws/vehicle
```

Choose the dashboard data mode with `DATA_MODE`. The default is `websocket`.

WebSocket mode:

```powershell
flutter run -d chrome --dart-define=DATA_MODE=websocket --dart-define=WS_URL=ws://127.0.0.1:8000/ws/vehicle
```

HTTP polling mode:

```powershell
flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8080 --dart-define=DATA_MODE=http --dart-define=API_URL=http://192.168.5.214:8000/api/mock/vehicle
```

Local demo mode:

```powershell
flutter run -d chrome --dart-define=DATA_MODE=demo
```

## Secret Handling

Do not commit real Tesla credentials, access tokens, refresh tokens, client secrets, Apple certificates, or other private keys. Use local environment files for development secrets and keep `.env` files out of version control.
