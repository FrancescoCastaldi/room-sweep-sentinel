# Room Sweep Sentinel (RF-Sweep)

Soluzione professionale full-stack per la bonifica ambientale elettronica (TSCM - Technical Surveillance Countermeasures) mirata a stanare microspie, microfoni ambientali e microtelecamere nascoste operanti su frequenze Wi-Fi e Bluetooth Low Energy (BLE).

Progettata specificamente per dispositivi **Android / Google Pixel** con interfaccia **Material You 3.0 (estetica 2026)**, architettura asincrona e conformita stringente alla Direttiva Europea **NIS 2** (D.Lgs. 138/2024).

---

## Caratteristiche Principali

- **Radar Sweep 360° Real-Time**: Display radar circolare animato a 60 FPS con decadimento a fosfori verdi/ciano e cerchi concentrici di prossimita (1m, 3m, 5m, 10m).
- **Tracker Prossimita Geiger (Caldo/Freddo)**: Modalita di pinpointing acustico e tattile proporzionale all'intensita del segnale RSSI per localizzare fisicamente il trasmettitore nel raggio di 50 cm.
- **Motore Euristico Anti-Spia**:
  - Riconoscimento OUI di chipset spia noti (Espressif ESP32/ESP8266, Tuya IoT, Raspberry Pi, Axis, Hikvision, Dahua).
  - Rilevamento beacon di localizzazione non autorizzati (Apple AirTag / FindMy, Tile, Samsung SmartTag).
  - Individuazione reti con SSID nascosto e pattern malevoli (`CAM-`, `IPCAM-`, `SPYCAM`, `HD-MINI`).
- **Conformita NIS 2 & Forense**:
  - Audit trail locale a prova di manomissione con catena crittografica ad hash **SHA-256**.
  - Zero esfiltrazione di dati su server cloud esterni (architettura Local-First).
  - Esportazione rapida del verbale in tabella strutturata (CSV, JSON, PDF) e scorciatoie di condivisione (Email, WhatsApp, Drive).
- **Integrazione Google Pixel & Play Protect Safe**:
  - Package ID: `com.francescocastaldi.roomsentinel`
  - Permessi granulari Android 12-16 (`NEARBY_WIFI_DEVICES`, `BLUETOOTH_SCAN` con flag `neverForLocation`).
  - Nessun blocco di sicurezza in fase di installazione o sideloading APK.
- **Workflow CI/CD GitHub Actions**:
  - Compilazione automatica dell'APK release su ogni tag e push con allegato scaricabile nei GitHub Releases.

---

## Architettura

```
room-sweep-sentinel/
├── backend/                  # API FastAPI asincrone, WebSocket e Threat Engine
│   ├── app/
│   │   ├── api/routes.py     # Endpoint REST e stream WebSocket /ws/live-stream
│   │   ├── models/device.py  # Modelli Pydantic
│   │   ├── services/         # OUI lookup, threat engine, RF scanner
│   │   ├── config.py
│   │   └── main.py
│   ├── tests/                # 29 test automatici pytest (100% pass)
│   └── requirements.txt
├── mobile_app/               # App Flutter Material You 3.0 per Android / Pixel
│   ├── android/              # Manifest conforme permessi Android 12-16
│   ├── lib/
│   │   ├── models/           # Modelli RF e serializzatori
│   │   ├── theme/            # Tema dark AMOLED, squircle r=28, neon palette
│   │   ├── services/         # Scanner service e audit logger SHA-256 NIS2
│   │   ├── widgets/          # Radar custom painter, Geiger sheet, Animated logo
│   │   └── screens/          # Radar sweep, Device list, Audit report
│   ├── test/                 # Test unitari modelli e regole
│   └── pubspec.yaml
└── .github/workflows/        # Compilazione e rilascio automatico APK
```

---

## Avvio Rapido

### Backend FastAPI
```bash
cd backend
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python -m pytest tests/ -v
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

### Mobile App Flutter
```bash
cd mobile_app
flutter pub get
flutter test
flutter run -d <id-google-pixel>
```

---

## Licenza
MIT License - Copyright (c) 2026 Francesco Castaldi.
