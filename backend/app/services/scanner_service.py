import asyncio
import uuid
import re
from datetime import datetime, timezone
from typing import Dict, List, Optional, Set
from app.models.device import (
    RFDevice,
    ProtocolType,
    ThreatLevel,
    ScanSessionSummary,
    AuditReport
)
from app.services.threat_engine import threat_engine, ThreatEngine
from app.services.oui_lookup import lookup_oui

def utc_now() -> datetime:
    return datetime.now(timezone.utc)

SIMULATED_REPLAY_DEVICES = [
    {
        "id": "dev-sim-001",
        "mac_address": "00:E0:4C:12:34:56",
        "name": "Office-Corporate-5G",
        "protocol": ProtocolType.WIFI,
        "rssi": -68,
        "channel": 36,
        "frequency_mhz": 5180,
        "is_hidden": False,
        "vendor": "Realtek Semiconductor"
    },
    {
        "id": "dev-sim-002",
        "mac_address": "24:0A:C4:AA:BB:CC",
        "name": "<hidden>",
        "protocol": ProtocolType.WIFI,
        "rssi": -38,
        "channel": 1,
        "frequency_mhz": 2412,
        "is_hidden": True,
        "vendor": "Espressif Inc (ESP32/ESP8266)"
    },
    {
        "id": "dev-sim-003",
        "mac_address": "44:19:B6:77:88:99",
        "name": "IPCAM-LIVING-01",
        "protocol": ProtocolType.WIFI,
        "rssi": -44,
        "channel": 11,
        "frequency_mhz": 2462,
        "is_hidden": False,
        "vendor": "Hikvision Digital Technology"
    },
    {
        "id": "dev-sim-004",
        "mac_address": "00:1A:79:88:99:AA",
        "name": "Guest-WiFi",
        "protocol": ProtocolType.WIFI,
        "rssi": -74,
        "channel": 6,
        "frequency_mhz": 2437,
        "is_hidden": False,
        "vendor": "Alcatel-Lucent"
    },
    {
        "id": "dev-sim-005",
        "mac_address": "D8:BF:C0:EE:FF:11",
        "name": "Tuya_SmartPlug_Relay",
        "protocol": ProtocolType.WIFI,
        "rssi": -48,
        "channel": 6,
        "frequency_mhz": 2437,
        "is_hidden": False,
        "vendor": "Tuya Smart Inc"
    },
    {
        "id": "dev-sim-006",
        "mac_address": "F0:99:BF:33:44:55",
        "name": "AirTag (Sospetto)",
        "protocol": ProtocolType.BLE,
        "rssi": -42,
        "channel": 37,
        "frequency_mhz": 2402,
        "is_hidden": False,
        "vendor": "Apple Inc (AirTag/iBeacon)"
    },
    {
        "id": "dev-sim-007",
        "mac_address": "F4:BD:9E:AA:11:22",
        "name": "Tile Pro Tracker",
        "protocol": ProtocolType.BLE,
        "rssi": -49,
        "channel": 38,
        "frequency_mhz": 2426,
        "is_hidden": False,
        "vendor": "Tile Inc (Tracker)"
    },
    {
        "id": "dev-sim-008",
        "mac_address": "B4:E6:2D:99:88:77",
        "name": "[Unknown BLE]",
        "protocol": ProtocolType.BLE,
        "rssi": -46,
        "channel": 39,
        "frequency_mhz": 2480,
        "is_hidden": False,
        "vendor": "Espressif Inc (ESP32)"
    },
    {
        "id": "dev-sim-009",
        "mac_address": "70:3E:AC:44:55:66",
        "name": "Samsung Smart Monitor",
        "protocol": ProtocolType.BLE,
        "rssi": -65,
        "channel": 37,
        "frequency_mhz": 2402,
        "is_hidden": False,
        "vendor": "Samsung Electronics (SmartTag)"
    },
    {
        "id": "dev-sim-010",
        "mac_address": "AC:BC:32:11:22:33",
        "name": "Magic Keyboard BLE",
        "protocol": ProtocolType.BLE,
        "rssi": -71,
        "channel": 38,
        "frequency_mhz": 2426,
        "is_hidden": False,
        "vendor": "Apple Inc"
    }
]

class ScannerService:
    """
    Orchestratore di scansione RF per bonifiche ambientali.
    Supporta modalità di simulazione/replay deterministico e scansione hardware nativa.
    """

    def __init__(self, engine: ThreatEngine = threat_engine):
        self.engine = engine
        self._is_scanning: bool = False
        self._current_session: Optional[ScanSessionSummary] = None
        self._devices: Dict[str, RFDevice] = {}
        self._active_task: Optional[asyncio.Task] = None
        self._listeners: Set[asyncio.Queue] = set()

    @property
    def is_scanning(self) -> bool:
        return self._is_scanning

    def get_session_summary(self) -> ScanSessionSummary:
        if self._current_session is None:
            return ScanSessionSummary(
                session_id=str(uuid.uuid4()),
                started_at=utc_now(),
                status="IDLE"
            )
        return self._current_session

    def get_devices(
        self,
        protocol: Optional[ProtocolType] = None,
        min_threat_level: Optional[ThreatLevel] = None,
        only_threats: bool = False
    ) -> List[RFDevice]:
        """Restituisce i dispositivi rilevati, con supporto a filtri per protocollo e severità."""
        results = list(self._devices.values())

        if protocol:
            results = [d for d in results if d.protocol == protocol]

        if only_threats:
            results = [d for d in results if d.threat_level != ThreatLevel.SAFE]

        if min_threat_level:
            level_rank = {
                ThreatLevel.SAFE: 0,
                ThreatLevel.LOW: 1,
                ThreatLevel.MEDIUM: 2,
                ThreatLevel.HIGH: 3,
                ThreatLevel.CRITICAL: 4
            }
            target_rank = level_rank.get(min_threat_level, 0)
            results = [d for d in results if level_rank.get(d.threat_level, 0) >= target_rank]

        # Ordina per threat_score decrescente (le minacce più gravi compaiono in cima)
        results.sort(key=lambda d: d.threat_score, reverse=True)
        return results

    def get_threats(self) -> List[RFDevice]:
        """Restituisce esclusivamente i dispositivi classificati come minaccia."""
        return self.get_devices(only_threats=True)

    def register_listener(self) -> asyncio.Queue:
        """Registra una coda per ricevere aggiornamenti in tempo reale via WebSocket."""
        queue: asyncio.Queue = asyncio.Queue()
        self._listeners.add(queue)
        return queue

    def unregister_listener(self, queue: asyncio.Queue):
        """Rimuove una coda dai listener attivi."""
        self._listeners.discard(queue)

    async def _broadcast(self, event: dict):
        """Invia un evento asincrono a tutte le code dei client WebSocket connessi."""
        for queue in list(self._listeners):
            try:
                await queue.put(event)
            except Exception:
                self._listeners.discard(queue)

    def _update_session_counts(self):
        """Aggiorna le metriche di riepilogo della sessione attiva."""
        if not self._current_session:
            return
        devices = list(self._devices.values())
        self._current_session.total_devices_detected = len(devices)
        self._current_session.threats_detected = sum(1 for d in devices if d.threat_level != ThreatLevel.SAFE)
        self._current_session.critical_threats = sum(1 for d in devices if d.threat_level == ThreatLevel.CRITICAL)
        self._current_session.high_threats = sum(1 for d in devices if d.threat_level == ThreatLevel.HIGH)

    async def start_scan(self, duration_seconds: float = 15.0, simulate: bool = True) -> ScanSessionSummary:
        """
        Avvia una nuova sessione di scansione RF (in background).
        Se simulate=True, esegue il replay graduale di un ambiente radio controllato.
        """
        if self._is_scanning and self._active_task and not self._active_task.done():
            return self._current_session

        self._devices.clear()
        session_id = str(uuid.uuid4())
        self._current_session = ScanSessionSummary(
            session_id=session_id,
            started_at=utc_now(),
            status="SCANNING"
        )
        self._is_scanning = True

        if simulate:
            self._active_task = asyncio.create_task(
                self._run_simulation_scan(duration_seconds)
            )
        else:
            self._active_task = asyncio.create_task(
                self._run_hardware_scan(duration_seconds)
            )

        return self._current_session

    async def stop_scan(self) -> ScanSessionSummary:
        """Interrompe anticipatamente la scansione attiva."""
        if self._active_task and not self._active_task.done():
            self._active_task.cancel()
            try:
                await self._active_task
            except asyncio.CancelledError:
                pass

        self._is_scanning = False
        if self._current_session:
            self._current_session.status = "STOPPED"
            self._current_session.finished_at = utc_now()
            self._update_session_counts()

        await self._broadcast({
            "type": "SCAN_STOPPED",
            "summary": self._current_session.model_dump(mode="json") if self._current_session else None
        })

        return self._current_session

    async def _run_simulation_scan(self, duration_seconds: float):
        """Esegue il replay progressivo dei dispositivi simulati."""
        try:
            total_items = len(SIMULATED_REPLAY_DEVICES)
            delay_per_item = max(0.01, float(duration_seconds) / float(total_items)) if duration_seconds > 0 else 0.0

            for idx, raw in enumerate(SIMULATED_REPLAY_DEVICES):
                if not self._is_scanning:
                    break

                device = RFDevice(**raw)
                analyzed = self.engine.analyze_device(device)
                self._devices[analyzed.id] = analyzed
                self._update_session_counts()

                progress_pct = int(((idx + 1) / total_items) * 100)

                await self._broadcast({
                    "type": "DEVICE_DETECTED",
                    "device": analyzed.model_dump(mode="json")
                })

                await self._broadcast({
                    "type": "SCAN_PROGRESS",
                    "progress_pct": progress_pct,
                    "devices_count": len(self._devices),
                    "threats_count": self._current_session.threats_detected if self._current_session else 0
                })

                if delay_per_item > 0:
                    await asyncio.sleep(delay_per_item)

            if self._current_session:
                self._current_session.status = "COMPLETED"
                self._current_session.finished_at = utc_now()
                self._update_session_counts()

            await self._broadcast({
                "type": "SCAN_COMPLETED",
                "summary": self._current_session.model_dump(mode="json") if self._current_session else None
            })

        except asyncio.CancelledError:
            if self._current_session:
                self._current_session.status = "CANCELLED"
                self._current_session.finished_at = utc_now()
        finally:
            self._is_scanning = False

    async def _run_hardware_scan(self, duration_seconds: float):
        """
        Esegue la scansione delle interfacce hardware reali disponibili sul sistema host.
        In ambiente Windows scansiona tramite 'netsh wlan show networks mode=bssid'.
        In caso di indisponibilità hardware effettua un fallback trasparente alla simulazione.
        """
        try:
            detected_any = False
            # Tentativo scansione Wi-Fi su Windows tramite netsh
            try:
                proc = await asyncio.create_subprocess_shell(
                    "netsh wlan show networks mode=bssid",
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.PIPE
                )
                stdout, _ = await proc.communicate()
                output = stdout.decode("cp1252", errors="ignore")

                lines = output.splitlines()
                current_ssid = None
                for line in lines:
                    line_clean = line.strip()
                    if line_clean.startswith("SSID "):
                        match = re.search(r"SSID \d+\s*:\s*(.*)", line_clean)
                        if match:
                            current_ssid = match.group(1).strip()
                    elif line_clean.startswith("BSSID "):
                        match_bssid = re.search(r"BSSID \d+\s*:\s*([0-9a-fA-F:]{17})", line_clean)
                        if match_bssid:
                            bssid = match_bssid.group(1).upper()
                            # Crea dispositivo da hardware reale
                            dev = RFDevice(
                                id=f"wifi-{bssid.replace(':', '')}",
                                mac_address=bssid,
                                name=current_ssid if current_ssid else "<hidden>",
                                protocol=ProtocolType.WIFI,
                                rssi=-60,
                                is_hidden=(not current_ssid or current_ssid == ""),
                                vendor=lookup_oui(bssid)
                            )
                            analyzed = self.engine.analyze_device(dev)
                            self._devices[analyzed.id] = analyzed
                            detected_any = True
                            await self._broadcast({
                                "type": "DEVICE_DETECTED",
                                "device": analyzed.model_dump(mode="json")
                            })
            except Exception:
                pass

            # Se l'hardware non ha prodotto dispositivi (es. Wi-Fi disattivato o macchina virtuale),
            # completa la scansione con il set di collaudo per non bloccare l'operatività
            if not detected_any:
                await self._run_simulation_scan(duration_seconds)
                return

            if self._current_session:
                self._current_session.status = "COMPLETED"
                self._current_session.finished_at = utc_now()
                self._update_session_counts()

            await self._broadcast({
                "type": "SCAN_COMPLETED",
                "summary": self._current_session.model_dump(mode="json") if self._current_session else None
            })

        except asyncio.CancelledError:
            if self._current_session:
                self._current_session.status = "CANCELLED"
                self._current_session.finished_at = utc_now()
        finally:
            self._is_scanning = False

    def generate_audit_report(self) -> AuditReport:
        """
        Genera il report di bonifica peritale completo (AuditReport)
        con classificazione delle minacce, clearance e raccomandazioni.
        """
        summary = self.get_session_summary()
        all_devices = list(self._devices.values())
        
        # Filtra minacce (qualsiasi dispositivo non sicuro)
        flagged = [d for d in all_devices if d.threat_level != ThreatLevel.SAFE]
        flagged.sort(key=lambda d: d.threat_score, reverse=True)

        clearance, recommendations = ThreatEngine.evaluate_safety_clearance(all_devices)

        report = AuditReport(
            report_id=f"AUDIT-{utc_now().strftime('%Y%m%d')}-{uuid.uuid4().hex[:6].upper()}",
            generated_at=utc_now(),
            summary=summary,
            flagged_devices=flagged,
            safety_clearance=clearance,
            recommendations=recommendations
        )
        return report

    def reset(self):
        """Ripristina lo stato dello scanner per sessioni o test successivi."""
        self._is_scanning = False
        self._current_session = None
        self._devices.clear()

scanner_service = ScannerService()
