from enum import Enum
from typing import Optional, List
from pydantic import BaseModel, Field
from datetime import datetime, timezone

def utc_now() -> datetime:
    return datetime.now(timezone.utc)

class ProtocolType(str, Enum):
    WIFI = "WIFI"
    BLE = "BLE"

class ThreatLevel(str, Enum):
    SAFE = "SAFE"
    LOW = "LOW"
    MEDIUM = "MEDIUM"
    HIGH = "HIGH"
    CRITICAL = "CRITICAL"

class RFDevice(BaseModel):
    id: str
    mac_address: str
    name: Optional[str] = "Dispositivo sconosciuto"
    protocol: ProtocolType
    rssi: int
    channel: Optional[int] = None
    frequency_mhz: Optional[int] = None
    is_hidden: bool = False
    vendor: str = "Sconosciuto"
    threat_score: int = Field(default=0, ge=0, le=100)
    threat_level: ThreatLevel = ThreatLevel.SAFE
    threat_reasons: List[str] = Field(default_factory=list)
    estimated_distance_meters: float = 5.0
    first_seen: datetime = Field(default_factory=utc_now)
    last_seen: datetime = Field(default_factory=utc_now)

class ScanSessionSummary(BaseModel):
    session_id: str
    started_at: datetime = Field(default_factory=utc_now)
    finished_at: Optional[datetime] = None
    total_devices_detected: int = 0
    threats_detected: int = 0
    critical_threats: int = 0
    high_threats: int = 0
    status: str = "IDLE"

class AuditReport(BaseModel):
    report_id: str
    generated_at: datetime = Field(default_factory=utc_now)
    summary: ScanSessionSummary
    flagged_devices: List[RFDevice]
    safety_clearance: str
    recommendations: List[str]

class StartScanRequest(BaseModel):
    duration_seconds: float = 15.0
    simulate: bool = True
