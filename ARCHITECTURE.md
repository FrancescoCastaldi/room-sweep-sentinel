# Specifiche Architetturali

## 1. Threat Engine Heuristics
Il motore assegna uno score di rischio da 0 a 100:
- +45 se il vendor OUI appartiene a produttori noti di telecamere spia o microchip IoT ad alto rischio (Espressif, Tuya, Hikvision, Dahua).
- +35 se la rete Wi-Fi trasmette con SSID nascosto in prossimita (RSSI > -55 dBm).
- +40 se il nome SSID corrisponde a regex di streaming cam (`CAM-.*`, `IPCAM-.*`, `SPY-.*`, `EZVIZ-.*`).
- +30 se e un beacon di tracciamento BLE (AirTag, Tile, SmartTag) statico nella stanza.
- +20 se la potenza RSSI > -45 dBm (distanza fisica stimata inferiore a 1.2 metri).

## 2. Modello di Propagazione RF (Log-Distance Path Loss)
La distanza d (in metri) viene calcolata dalla formula:
d = 10 ** ((P_tx - RSSI) / (10 * n))
con n = 2.4 (ambiente interno con ostacoli) e P_tx = -59 dBm per BLE e -40 dBm per Wi-Fi.
