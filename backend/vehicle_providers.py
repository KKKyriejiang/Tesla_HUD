import time
from abc import ABC, abstractmethod

from dashboard_schema import DashboardData, MediaInfo


class VehicleProviderNotImplementedError(RuntimeError):
    pass


class VehicleProvider(ABC):
    @abstractmethod
    def get_dashboard_data(self) -> DashboardData:
        raise NotImplementedError


class MockVehicleProvider(VehicleProvider):
    def get_dashboard_data(self) -> DashboardData:
        now = time.time()
        tick = int(now)
        speed_sequence = [72, 74, 77, 80, 82, 79, 76, 73, 70, 68, 71]
        speed_kmh = speed_sequence[tick % len(speed_sequence)]
        battery_percent = max(0, 84 - ((tick // 20) % 5))
        range_km = 386 - ((tick // 5) % 12)
        media_status = "playing" if tick % 12 < 9 else "paused"

        return DashboardData(
            timestamp=now,
            speed_kmh=speed_kmh,
            gear="D",
            battery_percent=battery_percent,
            range_km=range_km,
            media=MediaInfo(
                title="Mock Drive",
                artist="Tesla HUD",
                status=media_status,
                source="mock",
            ),
        )


class TeslaVehicleProvider(VehicleProvider):
    def get_dashboard_data(self) -> DashboardData:
        raise VehicleProviderNotImplementedError(
            "Tesla provider not implemented yet"
        )
