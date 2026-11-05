from typing import Dict, Optional

# OUI database focused on RF chipsets frequently found in hidden cameras, micro-bugs and IoT devices
KNOWN_OUIS: Dict[str, str] = {
    "24:0A:C4": "Espressif Inc (ESP32/ESP8266)",
    "30:AE:A4": "Espressif Inc (ESP32)",
    "84:F3:EB": "Espressif Inc (ESP8266)",
    "B4:E6:2D": "Espressif Inc (ESP32)",
    "DC:4F:22": "Espressif Inc (ESP32)",
    "A4:CF:12": "Espressif Inc (ESP32)",
    "D8:BF:C0": "Tuya Smart Inc",
    "10:D5:61": "Tuya Smart Inc",
    "50:8A:06": "Tuya Smart Inc",
    "68:57:2D": "Tuya Smart Inc",
    "B8:27:EB": "Raspberry Pi Foundation",
    "DC:A6:32": "Raspberry Pi Foundation",
    "E4:5F:01": "Raspberry Pi Foundation",
    "00:40:8C": "Axis Communications (IP Camera)",
    "AC:CC:8E": "Axis Communications (IP Camera)",
    "44:19:B6": "Hikvision Digital Technology",
    "54:C4:15": "Hikvision Digital Technology",
    "BC:5E:CD": "Hikvision Digital Technology",
    "3C:EF:8C": "Dahua Technology",
    "E0:50:8B": "Dahua Technology",
    "00:1A:79": "Alcatel-Lucent",
    "F0:99:BF": "Apple Inc (AirTag/iBeacon)",
    "AC:BC:32": "Apple Inc",
    "70:3E:AC": "Samsung Electronics (SmartTag)",
    "F4:BD:9E": "Tile Inc (Tracker)",
    "00:E0:4C": "Realtek Semiconductor",
}

SUSPICIOUS_VENDORS = [
    "Espressif",
    "Tuya",
    "Raspberry Pi",
    "Axis Communications",
    "Hikvision",
    "Dahua",
    "Tile Inc"
]

def lookup_oui(mac: str) -> str:
    cleaned = mac.upper().replace("-", ":")
    prefix = ":".join(cleaned.split(":")[:3]) if len(cleaned.split(":")) >= 3 else cleaned
    return KNOWN_OUIS.get(prefix, "Produttore non catalogato")

def is_suspicious_vendor(vendor: str) -> bool:
    return any(sus.lower() in vendor.lower() for sus in SUSPICIOUS_VENDORS)
