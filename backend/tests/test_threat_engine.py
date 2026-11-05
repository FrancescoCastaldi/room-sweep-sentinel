from app.services.threat_engine import threat_engine, ThreatEngine
from app.models.device import RFDevice, ProtocolType, ThreatLevel

def test_distance_calculation_wifi_and_ble():
    # Wi-Fi calibrato a -42 dBm per 1 metro
    dist_wifi_1m = ThreatEngine.calculate_distance(-42, ProtocolType.WIFI)
    assert 0.95 <= dist_wifi_1m <= 1.05

    # BLE calibrato a -59 dBm per 1 metro
    dist_ble_1m = ThreatEngine.calculate_distance(-59, ProtocolType.BLE)
    assert 0.95 <= dist_ble_1m <= 1.05

    # Segnale più forte -> distanza minore
    dist_strong = ThreatEngine.calculate_distance(-30, ProtocolType.WIFI)
    assert dist_strong < dist_wifi_1m

    # Segnale più debole -> distanza maggiore
    dist_weak = ThreatEngine.calculate_distance(-80, ProtocolType.WIFI)
    assert dist_weak > dist_wifi_1m

def test_ip_camera_pattern_detection():
    dev = RFDevice(
        id="cam-1",
        mac_address="00:40:8C:11:22:33",  # Axis Communications
        name="IPCAM-LIVING-ROOM",
        protocol=ProtocolType.WIFI,
        rssi=-48
    )
    analyzed = threat_engine.analyze_device(dev)
    assert analyzed.threat_score >= 40
    assert any("Pattern telecamera IP/microcamera" in r for r in analyzed.threat_reasons)

def test_hidden_ssid_detection():
    dev = RFDevice(
        id="hidden-1",
        mac_address="00:1A:79:AA:BB:CC",
        name="<hidden>",
        protocol=ProtocolType.WIFI,
        rssi=-65,
        is_hidden=True
    )
    analyzed = threat_engine.analyze_device(dev)
    assert analyzed.is_hidden is True
    assert any("SSID nascosto" in r for r in analyzed.threat_reasons)
    assert analyzed.threat_score >= 30

def test_espressif_high_rssi_threat():
    # Microcamera ESP32 a distanza ravvicinata (-35 dBm)
    dev = RFDevice(
        id="esp-crit",
        mac_address="24:0A:C4:01:02:03",
        name="ESP_CAM_01",
        protocol=ProtocolType.WIFI,
        rssi=-35
    )
    analyzed = threat_engine.analyze_device(dev)
    assert analyzed.threat_level == ThreatLevel.CRITICAL
    assert analyzed.threat_score >= 85
    assert any("prossimità estrema" in r for r in analyzed.threat_reasons)
    assert any("Espressif" in r for r in analyzed.threat_reasons)

def test_tuya_bug_detection():
    dev = RFDevice(
        id="tuya-1",
        mac_address="D8:BF:C0:11:22:33",
        name="Tuya_Socket_01",
        protocol=ProtocolType.WIFI,
        rssi=-45
    )
    analyzed = threat_engine.analyze_device(dev)
    assert analyzed.threat_level in (ThreatLevel.MEDIUM, ThreatLevel.HIGH)
    assert any("Tuya" in r for r in analyzed.threat_reasons)
    assert any("segnale RF elevato" in r for r in analyzed.threat_reasons)

def test_ble_tracker_airtag_and_tile():
    airtag = RFDevice(
        id="tag-1",
        mac_address="F0:99:BF:AA:BB:CC",
        name="AirTag (Non accoppiato)",
        protocol=ProtocolType.BLE,
        rssi=-42
    )
    analyzed_airtag = threat_engine.analyze_device(airtag)
    assert analyzed_airtag.threat_level in (ThreatLevel.HIGH, ThreatLevel.CRITICAL)
    assert any("Tracker di tracciamento" in r for r in analyzed_airtag.threat_reasons)

    tile = RFDevice(
        id="tag-2",
        mac_address="F4:BD:9E:11:22:33",
        name="Tile Pro",
        protocol=ProtocolType.BLE,
        rssi=-49
    )
    analyzed_tile = threat_engine.analyze_device(tile)
    assert analyzed_tile.threat_score >= 60
    assert any("Tracker di tracciamento" in r for r in analyzed_tile.threat_reasons)

def test_anonymous_ble_beacon_detection():
    beacon = RFDevice(
        id="ble-anon",
        mac_address="02:11:22:33:44:55",
        name="[Unknown BLE]",
        protocol=ProtocolType.BLE,
        rssi=-38
    )
    analyzed = threat_engine.analyze_device(beacon)
    assert analyzed.threat_score >= 35
    assert any("Beacon BLE anonimo a forte potenza" in r for r in analyzed.threat_reasons)

def test_safe_benign_device():
    safe_dev = RFDevice(
        id="safe-ap",
        mac_address="00:E0:4C:99:88:77",
        name="Office-Workstation-WiFi",
        protocol=ProtocolType.WIFI,
        rssi=-72
    )
    analyzed = threat_engine.analyze_device(safe_dev)
    assert analyzed.threat_level == ThreatLevel.SAFE
    assert analyzed.threat_score == 0
    assert len(analyzed.threat_reasons) == 0

def test_evaluate_safety_clearance():
    # Caso 1: presenza di dispositivo critico
    crit_dev = RFDevice(
        id="crit",
        mac_address="24:0A:C4:00:00:01",
        name="CAM-SPY",
        protocol=ProtocolType.WIFI,
        rssi=-35
    )
    analyzed_crit = threat_engine.analyze_device(crit_dev)
    clearance, recs = ThreatEngine.evaluate_safety_clearance([analyzed_crit])
    assert "PERICOLO CRITICO" in clearance
    assert len(recs) > 0
    assert any("Ispezionare visivamente" in r for r in recs)

    # Caso 2: soli dispositivi innocui
    safe_dev = RFDevice(
        id="safe",
        mac_address="00:E0:4C:00:00:01",
        name="Legitimate-AP",
        protocol=ProtocolType.WIFI,
        rssi=-75
    )
    analyzed_safe = threat_engine.analyze_device(safe_dev)
    clearance_safe, recs_safe = ThreatEngine.evaluate_safety_clearance([analyzed_safe])
    assert "AMBIENTE BONIFICATO" in clearance_safe
    assert len(recs_safe) > 0
