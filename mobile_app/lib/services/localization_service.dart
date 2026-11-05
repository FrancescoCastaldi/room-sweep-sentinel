import 'package:flutter/material.dart';

enum AppLanguage { it, en }

class LocalizationService extends ChangeNotifier {
  AppLanguage _currentLanguage = AppLanguage.en;

  AppLanguage get currentLanguage => _currentLanguage;
  bool get isEnglish => _currentLanguage == AppLanguage.en;
  String get flag => _currentLanguage == AppLanguage.en ? "🇬🇧" : "🇮🇹";

  void toggleLanguage() {
    _currentLanguage = _currentLanguage == AppLanguage.en ? AppLanguage.it : AppLanguage.en;
    notifyListeners();
  }

  void setLanguage(AppLanguage lang) {
    _currentLanguage = lang;
    notifyListeners();
  }

  static final Map<String, Map<AppLanguage, String>> _strings = {
    'app_title': {
      AppLanguage.en: 'Room Sweep Sentinel',
      AppLanguage.it: 'Room Sweep Sentinel',
    },
    'radar_sweep': {
      AppLanguage.en: '360° Radar Sweep',
      AppLanguage.it: 'Scansione Radar 360°',
    },
    'scanning_active': {
      AppLanguage.en: 'SWEEP IN PROGRESS',
      AppLanguage.it: 'BONIFICA IN CORSO',
    },
    'scanning_idle': {
      AppLanguage.en: 'SYSTEM READY',
      AppLanguage.it: 'SISTEMA PRONTO',
    },
    'threats_detected': {
      AppLanguage.en: 'Threats Detected',
      AppLanguage.it: 'Minacce Rilevate',
    },
    'safe_clearance': {
      AppLanguage.en: 'Room Cleared - No Spy Devices Found',
      AppLanguage.it: 'Stanza Bonificata - Nessuna Microspia Trovata',
    },
    'warning_clearance': {
      AppLanguage.en: 'Suspect Beacons/Hidden Transmitters Detected',
      AppLanguage.it: 'Rilevati Trasmettitori Nascosti o Beacon Sospetti',
    },
    'start_scan': {
      AppLanguage.en: 'START SWEEP',
      AppLanguage.it: 'AVVIA BONIFICA',
    },
    'stop_scan': {
      AppLanguage.en: 'STOP SWEEP',
      AppLanguage.it: 'FERMA BONIFICA',
    },
    'geiger_title': {
      AppLanguage.en: 'Geiger Proximity Pinpoint',
      AppLanguage.it: 'Localizzatore Geiger di Prossimità',
    },
    'geiger_subtitle': {
      AppLanguage.en: 'Hot/Cold distance tracker with haptic and audio click cadence',
      AppLanguage.it: 'Tracciamento caldo/freddo con cadenza acustica e vibrazione',
    },
    'distance_est': {
      AppLanguage.en: 'Estimated Distance',
      AppLanguage.it: 'Distanza Stimata',
    },
    'devices_tab': {
      AppLanguage.en: 'Transmitters',
      AppLanguage.it: 'Trasmettitori',
    },
    'audit_tab': {
      AppLanguage.en: 'NIS2 Audit',
      AppLanguage.it: 'Verbale NIS2',
    },
    'export_report': {
      AppLanguage.en: 'Export Forensic Log',
      AppLanguage.it: 'Esporta Verbale Forense',
    },
    'share_whatsapp': {
      AppLanguage.en: 'Share on WhatsApp',
      AppLanguage.it: 'Condividi su WhatsApp',
    },
    'share_email': {
      AppLanguage.en: 'Send via Email',
      AppLanguage.it: 'Invia per Email',
    },
  };

  String t(String key) {
    return _strings[key]?[_currentLanguage] ?? key;
  }
}