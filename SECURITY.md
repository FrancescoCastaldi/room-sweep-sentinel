# Security Policy & Conformita NIS 2

## Direttiva NIS 2 (EU 2022/2555 - D.Lgs. 138/2024)

Room Sweep Sentinel adotta un approccio **Security-by-Design** e **Security-by-Default**:

1. **Integrita Forense del Dato**:
   - Ogni rilevazione e sessione di scansione genera una voce nell'audit log locale.
   - Ogni record include il digest hash crittografico del record precedente:
     Hash_n = SHA-256(Record_n + Hash_{n-1})
   - Qualsiasi tentativo di alterare retroattivamente i log di scansione invalida la catena crittografica.

2. **Principio del Minimo Privilegio**:
   - Nessun accesso root richiesto.
   - L'accesso al Bluetooth (`BLUETOOTH_SCAN`) specifica esplicitamente il flag `neverForLocation` per prevenire l'accesso surrettizio alle coordinate GPS.
   - Il Wi-Fi opera esclusivamente tramite le API pubbliche di sistema `NEARBY_WIFI_DEVICES`.

3. **Privacy Assoluta (Local-First)**:
   - I dati di telemetria RF non vengono trasmessi a server terzi ne aggregati in cloud esterni.
   - La comunicazione tra backend locale e frontend avviene tramite TLS/WSS su interfaccia loopback o rete privata cifrata.
