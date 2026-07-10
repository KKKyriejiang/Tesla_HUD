# Tesla HUD

Tesla HUD is a mobile auxiliary dashboard for Tesla owners. It displays vehicle speed, gear, battery level, range, and media information.

## Tech Stack

- Backend: Python FastAPI
- Frontend: Flutter
- Communication: WebSocket
- Development mode: mock data first
- Future integration: Tesla Fleet API and Fleet Telemetry

## Core Rules

- Never commit real Tesla credentials, access tokens, refresh tokens, client secrets, Apple certificates, or other private keys.
- Keep mock mode working at all times. Development should be possible without Tesla API access.
- Do not implement safety-critical driving logic.
- Treat this app as an auxiliary HUD only. It is not a replacement for Tesla's official vehicle display.
- Keep the dashboard data schema stable between mock data and real Tesla data.
- Prefer small, testable changes.
- Add or update README instructions when adding new setup steps.
- Use a clear file structure and avoid overengineering.

## Development Guidance

- Start new backend work with FastAPI conventions and keep API/WebSocket handlers focused.
- Start new frontend work with Flutter conventions and keep UI components small and reusable.
- Prefer mock data providers before real Tesla integrations.
- When adding real Tesla Fleet API or Fleet Telemetry support, isolate credential handling and integration code from mock data paths.
- Keep WebSocket payloads explicit and versionable so mock and real data can share the same dashboard contract.
- Add focused tests for schema changes, mock data behavior, and WebSocket message handling.
