# Tesla HUD

Tesla HUD is a mobile auxiliary dashboard for Tesla owners. The project will provide a mock-first dashboard that can display vehicle speed, gear, battery level, range, and media information.

This app is not a replacement for Tesla's official vehicle display and must not implement safety-critical driving logic.

## Project Structure

```text
backend/
  .env.example
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

This repository currently contains the initial monorepo structure only. Tesla API integration has not been implemented.

## Secret Handling

Do not commit real Tesla credentials, access tokens, refresh tokens, client secrets, Apple certificates, or other private keys. Use local environment files for development secrets and keep `.env` files out of version control.
