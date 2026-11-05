import asyncio
import pytest
import pytest_asyncio
import httpx
from fastapi.testclient import TestClient
from app.main import app
from app.services.scanner_service import scanner_service

sync_client = TestClient(app)

@pytest_asyncio.fixture(autouse=True)
async def clean_scanner_state():
    """Ripristina lo stato dello scanner prima e dopo ciascun test."""
    await scanner_service.stop_scan()
    scanner_service.reset()
    yield
    await scanner_service.stop_scan()
    scanner_service.reset()

@pytest_asyncio.fixture
async def client():
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app),
        base_url="http://test"
    ) as ac:
        yield ac

@pytest.mark.asyncio
async def test_health_and_root(client):
    res_health = await client.get("/health")
    assert res_health.status_code == 200
    data_health = res_health.json()
    assert data_health["status"] == "OK"
    assert data_health["app"] == "Room Sweep Sentinel API"

    res_root = await client.get("/")
    assert res_root.status_code == 200
    data_root = res_root.json()
    assert data_root["status"] == "ONLINE"
    assert "docs_url" in data_root

@pytest.mark.asyncio
async def test_start_scan_and_get_devices(client):
    start_res = await client.post("/scan/start", json={"duration_seconds": 0.1, "simulate": True})
    assert start_res.status_code == 200
    summary = start_res.json()
    assert "session_id" in summary
    assert summary["status"] in ("SCANNING", "COMPLETED")

    # Attesa che la simulazione completi i cicli asincroni
    await asyncio.sleep(0.3)

    dev_res = await client.get("/scan/devices")
    assert dev_res.status_code == 200
    devices = dev_res.json()
    assert len(devices) > 0
    assert any(d["name"] == "IPCAM-LIVING-01" for d in devices)

@pytest.mark.asyncio
async def test_scan_status_endpoint(client):
    status_res = await client.get("/scan/status")
    assert status_res.status_code == 200
    data = status_res.json()
    assert "session_id" in data
    assert "total_devices_detected" in data

@pytest.mark.asyncio
async def test_device_filters(client):
    await client.post("/scan/start", json={"duration_seconds": 0.1, "simulate": True})
    await asyncio.sleep(0.3)

    # Filtro protocollo WIFI
    res_wifi = await client.get("/scan/devices?protocol=WIFI")
    assert res_wifi.status_code == 200
    wifi_devices = res_wifi.json()
    assert len(wifi_devices) > 0
    assert all(d["protocol"] == "WIFI" for d in wifi_devices)

    # Filtro protocollo BLE
    res_ble = await client.get("/scan/devices?protocol=BLE")
    assert res_ble.status_code == 200
    ble_devices = res_ble.json()
    assert len(ble_devices) > 0
    assert all(d["protocol"] == "BLE" for d in ble_devices)

    # Filtro only_threats
    res_threats_filter = await client.get("/scan/devices?only_threats=true")
    assert res_threats_filter.status_code == 200
    threats_only = res_threats_filter.json()
    assert len(threats_only) > 0
    assert all(d["threat_level"] != "SAFE" for d in threats_only)

@pytest.mark.asyncio
async def test_get_threats_endpoint(client):
    await client.post("/scan/start", json={"duration_seconds": 0.1, "simulate": True})
    await asyncio.sleep(0.3)

    res = await client.get("/scan/threats")
    assert res.status_code == 200
    threats = res.json()
    assert len(threats) > 0
    scores = [t["threat_score"] for t in threats]
    assert scores == sorted(scores, reverse=True)
    assert all(t["threat_level"] != "SAFE" for t in threats)

@pytest.mark.asyncio
async def test_audit_report_generation(client):
    await client.post("/scan/start", json={"duration_seconds": 0.1, "simulate": True})
    await asyncio.sleep(0.3)

    res = await client.get("/audit-report")
    assert res.status_code == 200
    report = res.json()
    assert "report_id" in report
    assert report["report_id"].startswith("AUDIT-")
    assert "safety_clearance" in report
    assert len(report["recommendations"]) > 0
    assert len(report["flagged_devices"]) > 0

@pytest.mark.asyncio
async def test_stop_scan_endpoint(client):
    await client.post("/scan/start", json={"duration_seconds": 10, "simulate": True})
    stop_res = await client.post("/scan/stop")
    assert stop_res.status_code == 200
    data = stop_res.json()
    assert data["status"] in ("STOPPED", "COMPLETED")

@pytest.mark.asyncio
async def test_audit_reset_endpoint(client):
    await client.post("/scan/start", json={"duration_seconds": 0.1, "simulate": True})
    await asyncio.sleep(0.3)
    devs_before = (await client.get("/scan/devices")).json()
    assert len(devs_before) > 0

    reset_res = await client.post("/audit-report/reset")
    assert reset_res.status_code == 200
    assert reset_res.json()["status"] == "RESET_OK"
    devs_after = (await client.get("/scan/devices")).json()
    assert len(devs_after) == 0

@pytest.mark.asyncio
async def test_api_prefixed_routes(client):
    res = await client.get("/api/scan/status")
    assert res.status_code == 200
    res_threats = await client.get("/api/scan/threats")
    assert res_threats.status_code == 200

@pytest.mark.asyncio
async def test_hardware_scan_invocation(client):
    # Esegue start_scan con simulate=False per verificare che gestisca l'hardware o il fallback senza errori
    res = await client.post("/scan/start", json={"duration_seconds": 0.1, "simulate": False})
    assert res.status_code == 200
    await asyncio.sleep(0.4)
    status_res = await client.get("/scan/status")
    assert status_res.status_code == 200

def test_websocket_live_stream_initial_state():
    with sync_client.websocket_connect("/ws/live-stream") as ws:
        msg = ws.receive_json()
        assert msg["type"] == "INITIAL_STATE"
        assert "devices" in msg
        assert "summary" in msg
        assert "is_scanning" in msg

def test_websocket_live_stream_broadcast():
    with sync_client.websocket_connect("/ws/live-stream") as ws:
        init_msg = ws.receive_json()
        assert init_msg["type"] == "INITIAL_STATE"

        # Avvio scansione
        res = sync_client.post("/scan/start", json={"duration_seconds": 0.1, "simulate": True})
        assert res.status_code == 200

        # Ricezione primo evento in tempo reale
        event = ws.receive_json()
        assert event["type"] in ("DEVICE_DETECTED", "SCAN_PROGRESS", "SCAN_COMPLETED")
