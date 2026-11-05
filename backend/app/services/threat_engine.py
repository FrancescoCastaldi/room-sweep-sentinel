import re
from typing import List, Tuple
from app.models.device import RFDevice, ProtocolType, ThreatLevel
from app.services.oui_lookup import lookup_oui, is_suspicious_vendor
from app.config import settings

IP_CAMERA_PATTERNS = [
    r"CAM-",
    r"IPCAM-",
    r"IP[-_]?CAM",
    r"SPY[-_]?CAM",
    r"HD[-_]?CAM",
    r"MINICAM",
    r"CCTV",
    r"DVR",
    r"NVR",
    r"WIRELESS[-_]?CAM",
    r"CAM_",
    r"EZVIZ",
    r"REOLINK",
    r"V380",
    r"XIAOVV",
    r"YI-",
    r"XIAOMI[-_]?CAM",
    r"DAHUA",
    r"HIKVISION",
    r"UVC-",
    r"WEBCAM"
]

TRACKER_PATTERNS = [
    r"AIRTAG",
    r"FIND[\s_-]?MY",
    r"TILE",
    r"SMARTTAG",
    r"GALAXY[\s_-]?TAG",
    r"CHIPOLO",
    r"ITAG",
    r"TRACKER"
]

class ThreatEngine:
    """Motore euristico di analisi e correlazione minacce RF (Wi-Fi e BLE)."""

    @staticmethod
    def calculate_distance(rssi: int, protocol: ProtocolType) -> float:
        """
        Calcola la distanza approssimativa in metri basata sul modello Log-Distance Path Loss.
        - Wi-Fi: TxPower @ 1m ~ -42 dBm, esponente di attenuazione n = 2.7
        - BLE: TxPower @ 1m ~ -59 dBm, esponente di attenuazione n = 2.2
        """
        if protocol == ProtocolType.WIFI:
            tx_power = -42.0
            n = 2.7
        else:
            tx_power = -59.0
            n = 2.2

        exponent = (tx_power - float(rssi)) / (10.0 * n)
        distance = 10.0 ** exponent
        # Clamp tra 0.1m e 50.0m
        distance = max(0.1, min(50.0, distance))
        return round(distance, 2)

    def analyze_device(self, device: RFDevice) -> RFDevice:
        """
        Analizza un dispositivo rilevato applicando l'insieme di regole euristiche.
        Calcola la distanza stimata, il punteggio di minaccia (0-100), il livello e le motivazioni.
        """
        # Risoluzione automatica del vendor tramite OUI se non ancora noto
        if not device.vendor or device.vendor in ("Sconosciuto", "Produttore non catalogato"):
            device.vendor = lookup_oui(device.mac_address)

        # Calcolo distanza
        device.estimated_distance_meters = self.calculate_distance(device.rssi, device.protocol)

        score = 0
        reasons: List[str] = []
        name_clean = (device.name or "").strip()
        name_upper = name_clean.upper()
        vendor_clean = device.vendor or ""

        # 1. Analisi pattern SSID / Telecamere IP / Microcamere spia
        matched_cam = None
        for pattern in IP_CAMERA_PATTERNS:
            if re.search(pattern, name_upper):
                matched_cam = pattern
                break
        
        if matched_cam:
            score += 45
            reasons.append(f"Pattern telecamera IP/microcamera rilevato nel nome/SSID ('{name_clean}')")

        # 2. Analisi SSID nascosti (Wi-Fi)
        is_hidden_network = (
            device.protocol == ProtocolType.WIFI and (
                device.is_hidden or
                not name_clean or
                name_clean.lower() in ("<hidden>", "[nascosto]", "hidden ssid", "wildcard", "hidden")
            )
        )
        if is_hidden_network:
            score += 30
            device.is_hidden = True
            reasons.append("Rete Wi-Fi con SSID nascosto (tentativo di occultamento radio o rogue AP)")

        # 3. Analisi Chipset IoT ad alto rischio (Espressif, Tuya, Raspberry Pi)
        is_espressif = "espressif" in vendor_clean.lower()
        is_tuya = "tuya" in vendor_clean.lower()
        is_other_suspicious = any(sus.lower() in vendor_clean.lower() for sus in ["raspberry pi", "axis", "hikvision", "dahua"])

        if is_espressif or is_tuya:
            score += 35
            reasons.append(f"Chipset IoT {vendor_clean} ad alta incidenza in microspie e microcamere spia")

            if device.rssi >= settings.RSSI_CRITICAL_THRESHOLD:
                score += 30
                reasons.append(
                    f"Chipset {vendor_clean} a prossimità estrema ({device.rssi} dBm, ~{device.estimated_distance_meters}m) - probabile microspia celata"
                )
            elif device.rssi >= settings.RSSI_PROXIMITY_THRESHOLD:
                score += 20
                reasons.append(
                    f"Chipset {vendor_clean} con segnale RF elevato ({device.rssi} dBm, ~{device.estimated_distance_meters}m)"
                )
        elif is_other_suspicious:
            score += 25
            reasons.append(f"Dispositivo sorveglianza/computazionale ({vendor_clean}) presente nell'area")
            if device.rssi >= settings.RSSI_PROXIMITY_THRESHOLD:
                score += 15
                reasons.append(f"Segnale elevato da dispositivo {vendor_clean} ({device.rssi} dBm)")

        # 4. Analisi Tracker BLE & Apple FindMy / AirTag / Tile / SmartTag
        is_tracker = False
        matched_tracker = None
        for pattern in TRACKER_PATTERNS:
            if re.search(pattern, name_upper):
                is_tracker = True
                matched_tracker = pattern
                break

        if not is_tracker and any(brand in vendor_clean.lower() for brand in ["tile inc", "airtag", "smarttag"]):
            is_tracker = True
            matched_tracker = vendor_clean

        if is_tracker:
            score += 45
            reasons.append(f"Beacon/Tracker di tracciamento rilevato ({name_clean or vendor_clean}) - possibile localizzazione occulta/stalking")
            if device.rssi >= settings.RSSI_CRITICAL_THRESHOLD:
                score += 30
                reasons.append(f"Tracker a distanza ravvicinata ({device.rssi} dBm, ~{device.estimated_distance_meters}m) - sospetto occultamento in bagaglio o arredo")
            elif device.rssi >= settings.RSSI_PROXIMITY_THRESHOLD:
                score += 20
                reasons.append(f"Tracker a medio-corto raggio ({device.rssi} dBm, ~{device.estimated_distance_meters}m)")

        # 5. Analisi Beacon BLE anonimi / non associati a forte intensità
        if device.protocol == ProtocolType.BLE and not is_tracker:
            is_generic_name = (
                not name_clean or
                name_clean.lower() in ("dispositivo sconosciuto", "[unknown ble]", "unknown", "beacon", "ibeacon", "eddystone")
            )
            if is_generic_name:
                if device.rssi >= settings.RSSI_CRITICAL_THRESHOLD:
                    score += 35
                    reasons.append(f"Beacon BLE anonimo a forte potenza ({device.rssi} dBm, ~{device.estimated_distance_meters}m) - possibile trasmettitore occulto")
                elif device.rssi >= settings.RSSI_PROXIMITY_THRESHOLD:
                    score += 20
                    reasons.append(f"Beacon BLE anonimo in prossimità ({device.rssi} dBm, ~{device.estimated_distance_meters}m)")

        # 6. Correzione di prossimità generale per segnali critici
        if device.rssi >= settings.RSSI_CRITICAL_THRESHOLD and len(reasons) > 0:
            if not any("prossimità estrema" in r or "distanza ravvicinata" in r or "forte potenza" in r for r in reasons):
                score += 15
                reasons.append(f"Segnale RF critico ({device.rssi} dBm) - distanza stimata inferiore a 1 metro")

        # Clamp finale dello score tra 0 e 100
        final_score = max(0, min(100, score))
        device.threat_score = final_score
        device.threat_reasons = reasons

        # Mappatura ThreatLevel
        if final_score >= 85:
            device.threat_level = ThreatLevel.CRITICAL
        elif final_score >= 65:
            device.threat_level = ThreatLevel.HIGH
        elif final_score >= 40:
            device.threat_level = ThreatLevel.MEDIUM
        elif final_score >= 20:
            device.threat_level = ThreatLevel.LOW
        else:
            device.threat_level = ThreatLevel.SAFE

        return device

    def analyze_devices(self, devices: List[RFDevice]) -> List[RFDevice]:
        """Analizza una lista di dispositivi RF aggiornandone i parametri di minaccia."""
        return [self.analyze_device(d) for d in devices]

    @staticmethod
    def evaluate_safety_clearance(devices: List[RFDevice]) -> Tuple[str, List[str]]:
        """
        Valuta lo stato complessivo di sicurezza dell'ambiente scansionato
        e genera raccomandazioni operative per l'operatore di bonifica.
        """
        critical_count = sum(1 for d in devices if d.threat_level == ThreatLevel.CRITICAL)
        high_count = sum(1 for d in devices if d.threat_level == ThreatLevel.HIGH)
        medium_count = sum(1 for d in devices if d.threat_level == ThreatLevel.MEDIUM)

        recommendations: List[str] = []

        if critical_count > 0:
            clearance = "PERICOLO CRITICO - TRASMETTITORI OCCULTATI RILEVATI"
            recommendations.append("Scollegare o schermare immediatamente i trasmettitori ad alta potenza RF rilevati nel raggio di 1 metro.")
            recommendations.append("Ispezionare visivamente prese elettriche a muro, rilevatori fumo, lampade e quadri per microcamere Espressif/Tuya.")
            recommendations.append("Ispezionare borse, tasche e indumenti per la presenza di tag di tracciamento o beacon Apple FindMy/Tile.")
            recommendations.append("Sospendere qualsiasi colloquio o attività confidenziale fino alla rimozione fisica dei dispositivi segnalati.")
        elif high_count > 0:
            clearance = "ATTENZIONE ELEVATA - DISPOSITIVI SOSPETTI PRESENTI"
            recommendations.append("Localizzare tramite la visualizzazione Radar i dispositivi con segnale superiore a -50 dBm.")
            recommendations.append("Verificare se i dispositivi Wi-Fi/BLE rilevati corrispondono a utenze legittime dell'edificio.")
            recommendations.append("Eseguire una seconda scansione a distanza di 5 minuti per confermare la stazionarietà del segnale.")
        elif medium_count > 0:
            clearance = "ATTENZIONE MEDIA - RILEVATE ANOMALIE RF LIEVI"
            recommendations.append("Verificare l'origine dei SSID Wi-Fi nascosti o delle trasmissioni BLE anonime.")
            recommendations.append("Mantenere attivo il monitoraggio live stream durante la permanenza nella stanza.")
        else:
            clearance = "AMBIENTE BONIFICATO - NESSUNA MINACCIA RILEVATA"
            recommendations.append("Lo spettro radio analizzato non evidenzia trasmettitori spia o pattern ostili nelle vicinanze.")
            recommendations.append("Si consiglia una scansione periodica prima di ogni sessione di lavoro riservata.")

        return clearance, recommendations

threat_engine = ThreatEngine()
