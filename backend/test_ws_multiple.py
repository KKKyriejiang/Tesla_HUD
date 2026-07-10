import asyncio
import websockets

async def main():
    async with websockets.connect("ws://127.0.0.1:8000/ws/vehicle") as ws:
        for i in range(5):
            msg = await ws.recv()
            print(f"Message {i + 1}: {msg}")

asyncio.run(main())
