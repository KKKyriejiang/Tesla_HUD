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

Backend commands must be run from the `backend` directory.

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

Provider-backed dashboard data:

```text
http://127.0.0.1:8000/api/dashboard
```

Mock vehicle WebSocket:

```text
ws://127.0.0.1:8000/ws/vehicle
```

The backend uses `DATA_PROVIDER=mock` by default. Mock mode keeps `/api/mock/vehicle`, `/api/dashboard`, and `/ws/vehicle` working without Tesla credentials.

```powershell
$env:DATA_PROVIDER="mock"
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

`DATA_PROVIDER=tesla` is reserved for future Tesla Fleet API work and currently returns `Tesla provider not implemented yet`.

Run backend tests from `backend`:

```powershell
.\.venv\Scripts\python.exe -m pytest
```

## Mobile Development

Flutter commands must be run from the `mobile/tesla_hud_app` directory.

From PowerShell:

```powershell
cd mobile\tesla_hud_app
flutter pub get
```

Choose the dashboard data mode with `DATA_MODE`. The default is `websocket`.

### Demo Mode

Demo mode runs entirely in Flutter and does not require the backend.

```powershell
flutter run -d chrome --dart-define=DATA_MODE=demo
```

### Local WebSocket Mode

Start the backend first from `backend`, then run the Flutter app from `mobile/tesla_hud_app`.

```powershell
flutter run -d chrome --dart-define=DATA_MODE=websocket --dart-define=WS_URL=ws://127.0.0.1:8000/ws/vehicle
```

### iPhone HTTP Mode

Use HTTP mode when testing the Flutter web app from iPhone Safari. Replace `<WINDOWS_IP>` with the LAN IP address of the Windows machine running the backend.

iPhone Safari Web cannot reliably force landscape orientation from Flutter. Rotate the phone manually; portrait mode shows a rotate prompt, and landscape mode shows the full HUD.

Start the backend from `backend`:

```powershell
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

Start Flutter from `mobile/tesla_hud_app`:

```powershell
flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8080 --dart-define=DATA_MODE=http --dart-define=API_URL=http://<WINDOWS_IP>:8000/api/mock/vehicle
```

Then open this from iPhone Safari:

```text
http://<WINDOWS_IP>:8080
```

Verify the iPhone can reach the backend directly:

```text
http://<WINDOWS_IP>:8000/api/mock/vehicle
```

## Troubleshooting

### No pubspec.yaml file found

Run Flutter commands from `mobile/tesla_hud_app`, not from the repository root.

```powershell
cd mobile\tesla_hud_app
flutter pub get
```

### iPhone cannot access backend

Make sure the backend is running from `backend` with `--host 0.0.0.0`.

```powershell
cd backend
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

On the iPhone, test the backend URL directly in Safari:

```text
http://<WINDOWS_IP>:8000/api/mock/vehicle
```

The iPhone and Windows machine must be on the same Wi-Fi or LAN.

### Disconnected status

For iPhone Safari, prefer `DATA_MODE=http` first. Some local networks or browsers may block WebSocket traffic even when HTTP works.

Check that the URL passed through `--dart-define` matches the selected mode:

- `DATA_MODE=websocket` uses `WS_URL=ws://.../ws/vehicle`
- `DATA_MODE=http` uses `API_URL=http://.../api/mock/vehicle`
- `DATA_MODE=demo` does not use the backend

### Mobile overflow or max pixel display issues

Rotate the iPhone to landscape before using HUD mode. Portrait mode intentionally shows:

```text
Rotate your phone for HUD mode
```

If landscape still looks too large, refresh Safari after rotating the phone. Also make sure Safari is not zoomed in and that the app is running the latest Flutter build after code changes.

### Wrong IP address

Do not use `127.0.0.1` from iPhone Safari. On the iPhone, `127.0.0.1` means the iPhone itself, not the Windows machine.

Find the Windows LAN IP address with:

```powershell
ipconfig
```

Use the IPv4 address for the active Wi-Fi or Ethernet adapter.

### Windows firewall

If the iPhone cannot open `http://<WINDOWS_IP>:8000/api/mock/vehicle`, Windows Firewall may be blocking inbound connections.

Allow inbound access for the backend port `8000` and Flutter web-server port `8080`, or allow the Python and Flutter/Dart processes when Windows prompts for network access.

## Secret Handling

Do not commit real Tesla credentials, access tokens, refresh tokens, client secrets, Apple certificates, or other private keys. Use local environment files for development secrets and keep `.env` files out of version control.
