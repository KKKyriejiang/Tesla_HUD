import asyncio
import websockets

async def main():
    async with websockets.connect("ws://127.0.0.1:8000/ws/vehicle") as ws:
        msg = await ws.recv()
        print(msg)

asyncio.run(main())
