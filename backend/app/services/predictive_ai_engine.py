from typing import List, Dict, Optional
import math
from datetime import datetime, timezone
from pydantic import BaseModel

class TransmissionPulse(BaseModel):
    timestamp_utc: datetime
    rssi: int
    packet_size: int

class AnomalyPrediction(BaseModel):
    device_id: str
    is_anomaly: bool
    confidence_score: float  # 0.0 to 1.0
    pattern_type: str        # CONTINUOUS, PERIODIC_BURST, STEALTH_SLEEP, BENIGN
    predicted_next_transmission_sec: Optional[float] = None
    threat_summary: str

class PredictiveAIEngine:
    """
    Time-series RF telemetry analysis engine.
    Detects covert spy transmitters using burst transmission, beacon jitter, and sleeping cycles.
    """
    def __init__(self):
        self._history: Dict[str, List[TransmissionPulse]] = {}

    def record_pulse(self, device_id: str, rssi: int, packet_size: int = 64) -> None:
        if device_id not in self._history:
            self._history[device_id] = []
        self._history[device_id].append(
            TransmissionPulse(
                timestamp_utc=datetime.now(timezone.utc),
                rssi=rssi,
                packet_size=packet_size
            )
        )
        # Keep sliding window of last 50 pulses
        if len(self._history[device_id]) > 50:
            self._history[device_id].pop(0)

    def analyze_device_behavior(self, device_id: str, is_known_threat: bool = False) -> AnomalyPrediction:
        pulses = self._history.get(device_id, [])
        if len(pulses) < 3:
            return AnomalyPrediction(
                device_id=device_id,
                is_anomaly=False,
                confidence_score=0.15,
                pattern_type="BENIGN",
                threat_summary="Dati insufficienti per predizione comportamentale (campioni < 3)."
            )

        # 1. Delta intervals in seconds
        deltas = [
            (pulses[i].timestamp_utc - pulses[i-1].timestamp_utc).total_seconds()
            for i in range(1, len(pulses))
        ]
        mean_delta = sum(deltas) / len(deltas) if deltas else 1.0
        variance = sum((d - mean_delta) ** 2 for d in deltas) / len(deltas) if deltas else 0.0
        std_dev = math.sqrt(variance)

        # 2. Check for periodic covert beaconing (low standard deviation on intervals)
        is_clockwork_periodic = std_dev < 0.25 and len(pulses) >= 4

        # 3. Check for RSSI stability (fixed hidden spy vs moving phone)
        rssis = [p.rssi for p in pulses]
        rssi_variance = sum((r - (sum(rssis) / len(rssis))) ** 2 for r in rssis) / len(rssis)

        if is_clockwork_periodic and rssi_variance < 3.0:
            confidence = min(0.95, 0.65 + (0.25 if is_known_threat else 0.10))
            return AnomalyPrediction(
                device_id=device_id,
                is_anomaly=True,
                confidence_score=round(confidence, 2),
                pattern_type="PERIODIC_BURST",
                predicted_next_transmission_sec=round(mean_delta, 2),
                threat_summary="Rilevata trasmissione a intervalli esatti e segnale stazionario: comportamento tipico di microspia o registratore burst."
            )

        # 4. Check for high-volume streaming (IP cameras)
        if mean_delta < 0.1:
            return AnomalyPrediction(
                device_id=device_id,
                is_anomaly=True,
                confidence_score=0.88,
                pattern_type="CONTINUOUS",
                threat_summary="Flusso RF continuo ad alta frequenza: compatibile con streaming video live nascosto."
            )

        return AnomalyPrediction(
            device_id=device_id,
            is_anomaly=False,
            confidence_score=0.10,
            pattern_type="BENIGN",
            threat_summary="Pattern di emissione conforme a normale traffico dati o periferica passiva."
        )

predictive_ai_engine = PredictiveAIEngine()
