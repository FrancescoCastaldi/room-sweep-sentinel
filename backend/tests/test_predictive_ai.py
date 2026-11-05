from datetime import datetime, timedelta
from app.services.predictive_ai_engine import PredictiveAIEngine, TransmissionPulse

def test_insufficient_samples():
    engine = PredictiveAIEngine()
    engine.record_pulse("device-1", -60)
    pred = engine.analyze_device_behavior("device-1")
    assert pred.is_anomaly is False
    assert "Dati insufficienti" in pred.threat_summary

def test_clockwork_spy_transmitter():
    engine = PredictiveAIEngine()
    base_time = datetime(2026, 11, 5, 23, 0, 0)
    # Inject 5 pulses exactly 2.0 seconds apart with identical RSSI -42
    engine._history["spy-mic-1"] = [
        TransmissionPulse(timestamp_utc=base_time + timedelta(seconds=i * 2.0), rssi=-42, packet_size=128)
        for i in range(5)
    ]
    pred = engine.analyze_device_behavior("spy-mic-1", is_known_threat=True)
    assert pred.is_anomaly is True
    assert pred.pattern_type == "PERIODIC_BURST"
    assert pred.confidence_score >= 0.85
    assert pred.predicted_next_transmission_sec == 2.0

def test_benign_random_traffic():
    engine = PredictiveAIEngine()
    base_time = datetime(2026, 11, 5, 23, 0, 0)
    # Irregular intervals and varying RSSI (person walking with smartphone)
    delays = [0, 1.2, 5.8, 8.1, 14.2]
    rssis = [-75, -60, -82, -55, -70]
    engine._history["normal-phone"] = [
        TransmissionPulse(timestamp_utc=base_time + timedelta(seconds=delays[i]), rssi=rssis[i], packet_size=64)
        for i in range(len(delays))
    ]
    pred = engine.analyze_device_behavior("normal-phone")
    assert pred.is_anomaly is False
    assert pred.pattern_type == "BENIGN"
