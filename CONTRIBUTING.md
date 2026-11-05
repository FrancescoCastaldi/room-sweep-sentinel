# Guida per i Contributori

1. Esegui il fork del repository e crea un branch dedicato (`git checkout -b feature/nuova-funzionalita`).
2. Mantieni lo stile architetturale e la codifica UTF-8 pura senza BOM.
3. Esegui la suite di test completa prima di proporre una PR:
   - Backend: `python -m pytest backend/tests/ -v`
   - Frontend: `cd mobile_app && flutter test`
4. Invia una Pull Request con descrizione dettagliata delle modifiche.
