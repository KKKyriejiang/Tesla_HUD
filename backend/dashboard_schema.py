from typing import Literal

from pydantic import BaseModel


Gear = Literal["P", "N", "D", "R"]
MediaStatus = Literal["playing", "paused"]


class MediaInfo(BaseModel):
    title: str
    artist: str
    status: MediaStatus
    source: str


class DashboardData(BaseModel):
    timestamp: float
    speed_kmh: float
    gear: Gear
    battery_percent: float
    range_km: float
    media: MediaInfo
