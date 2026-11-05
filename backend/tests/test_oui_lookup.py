from app.services.oui_lookup import lookup_oui, is_suspicious_vendor

def test_lookup_known_espressif():
    mac = "24:0A:C4:11:22:33"
    vendor = lookup_oui(mac)
    assert "Espressif" in vendor

def test_lookup_known_tuya():
    mac = "D8:BF:C0:AA:BB:CC"
    vendor = lookup_oui(mac)
    assert "Tuya" in vendor

def test_lookup_known_hikvision():
    mac = "44:19:B6:55:66:77"
    vendor = lookup_oui(mac)
    assert "Hikvision" in vendor

def test_lookup_known_apple_airtag():
    mac = "F0:99:BF:01:02:03"
    vendor = lookup_oui(mac)
    assert "Apple Inc" in vendor

def test_lookup_known_tile():
    mac = "F4:BD:9E:04:05:06"
    vendor = lookup_oui(mac)
    assert "Tile Inc" in vendor

def test_lookup_unknown_mac():
    mac = "02:00:00:11:22:33"
    vendor = lookup_oui(mac)
    assert vendor == "Produttore non catalogato"

def test_lookup_format_variations():
    # Minuscold e separatori a trattino
    mac_dash = "24-0a-c4-aa-bb-cc"
    vendor = lookup_oui(mac_dash)
    assert "Espressif" in vendor

    # Solo prefisso OUI
    prefix = "30:ae:a4"
    vendor_prefix = lookup_oui(prefix)
    assert "Espressif" in vendor_prefix

def test_is_suspicious_vendor():
    assert is_suspicious_vendor("Espressif Inc (ESP32)") is True
    assert is_suspicious_vendor("Tuya Smart Inc") is True
    assert is_suspicious_vendor("Raspberry Pi Foundation") is True
    assert is_suspicious_vendor("Hikvision Digital Technology") is True
    assert is_suspicious_vendor("Dahua Technology") is True
    assert is_suspicious_vendor("Axis Communications (IP Camera)") is True
    assert is_suspicious_vendor("Tile Inc (Tracker)") is True

    # Produttori legittimi/innocui
    assert is_suspicious_vendor("Realtek Semiconductor") is False
    assert is_suspicious_vendor("Alcatel-Lucent") is False
    assert is_suspicious_vendor("Cisco Systems") is False
    assert is_suspicious_vendor("Produttore non catalogato") is False
