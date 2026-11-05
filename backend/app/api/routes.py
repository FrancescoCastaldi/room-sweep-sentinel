import asyncio
import logging
from typing import List, Optional
from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Query, Body, status
from app.models.device import (
    RFDevice,
    ProtocolType,
    ThreatLevel,
    ScanSessionSummary,
    AuditReport,
    StartScanRequest
)
from app.services.scanner_service import scanner_service

logger = logging.getLogger("room-sweep-sentinel.api")

router = APIRouter()

@router.post("/scan/start", response_model=ScanSessionSummary, status_code=status.HTTP_200_OK)
async def start_scan(request: Optional[StartScanRequest] = None):
    """Avvia una scansione RF dello spettro radio Wi-Fi e BLE."""
    req = request or StartScanRequest()
    summary = await scanner_service.start_scan(
        duration_seconds=req.duration_seconds,
        simulate=req.simulate
    )
    return summary

@router.post("/scan/stop", response_model=ScanSessionSummary, status_code=status.HTTP_200_OK)
async def stop_scan():
    """Interrompe anticipatamente la sessione di scansione in corso."""
    summary = await scanner_service.stop_scan()
    return summary

@router.get("/scan/status", response_model=ScanSessionSummary)
async def get_scan_status():
    """Restituisce lo stato corrente della scansione e i contatori di rilevamento."""
    return scanner_service.get_session_summary()

@router.get("/scan/devices", response_model=List[RFDevice])
async def get_devices(
    protocol: Optional[ProtocolType] = Query(None, description="Filtra per tipologia di protocollo (WIFI o BLE)"),
    min_threat_level: Optional[ThreatLevel] = Query(None, description="Livello minimo di minaccia"),
    only_threats: bool = Query(False, description="Se True, restituisce solo apparati sospetti/pericolosi")
):
    """Restituisce l'elenco dei dispositivi RF intercettati nella sessione corrente."""
    return scanner_service.get_devices(
        protocol=protocol,
        min_threat_level=min_threat_level,
        only_threats=only_threats
    )

@router.get("/scan/threats", response_model=List[RFDevice])
async def get_threats():
    """Restituisce esclusivamente i trasmettitori classificati come minaccia (ordinati per gravità)."""
    return scanner_service.get_threats()

@router.get("/audit-report", response_model=AuditReport)
async def get_audit_report():
    """Genera il rapporto peritale completo di bonifica ambientale (Audit Report)."""
    return scanner_service.generate_audit_report()

@router.post("/audit-report/reset")
async def reset_audit():
    """Azzera la sessione e lo storico dei dispositivi per una nuova ispezione."""
    scanner_service.reset()
    return {"status": "RESET_OK", "message": "Sessione azzerata con successo."}

@router.websocket("/ws/live-stream")
async def websocket_live_stream(websocket: WebSocket):
    """
    Canale WebSocket per aggiornamenti in tempo reale su radar, card e stato di scansione.
    All'apertura della connessione trasmette lo snapshot iniziale, dopodiché diffonde
    gli eventi di rilevamento DEVICE_DETECTED, SCAN_PROGRESS e SCAN_COMPLETED.
    """
    await websocket.accept()
    queue = scanner_service.register_listener()

    try:
        # Trasmissione stato iniziale
        current_devices = [
            d.model_dump(mode="json")
            for d in scanner_service.get_devices()
        ]
        initial_payload = {
            "type": "INITIAL_STATE",
            "is_scanning": scanner_service.is_scanning,
            "summary": scanner_service.get_session_summary().model_dump(mode="json"),
            "devices": current_devices
        }
        await websocket.send_json(initial_payload)

        # Loop di ricezione e invio asincrono
        while True:
            # Attendiamo il prossimo evento dalla coda degli aggiornamenti
            event = await queue.get()
            await websocket.send_json(event)
    except WebSocketDisconnect:
        logger.info("Client WebSocket disconnesso normalmente.")
    except Exception as e:
        logger.warning(f"Chiusura connessione WebSocket: {e}")
    finally:
        scanner_service.unregister_listener(queue)
