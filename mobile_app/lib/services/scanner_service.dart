import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/device_model.dart';

class ScannerService extends ChangeNotifier {
  bool _isScanning = false;
  List<RFDevice> _devices = [];
  RFDevice? _selectedGeigerTarget;
  Timer? _scanTimer;
  Timer? _geigerTimer;
  DateTime? _scanStartTime;
  double _radarAngle = 0.0;
  Timer? _radarAnimationTimer;

  bool get isScanning => _isScanning;
  List<RFDevice> get devices => List.unmodifiable(_devices);
  RFDevice? get selectedGeigerTarget => _selectedGeigerTarget;
  double get radarAngle => _radarAngle;
  DateTime? get scanStartTime => _scanStartTime;

  List<RFDevice> get criticalThreats =>
      _devices.where((d) => d.threatLevel == ThreatLevel.CRITICAL).toList();

  List<RFDevice> get highThreats =>
      _devices.where((d) => d.threatLevel == ThreatLevel.HIGH).toList();

  List<RFDevice> get mediumThreats =>
      _devices.where((d) => d.threatLevel == ThreatLevel.MEDIUM).toList();

  List<RFDevice> get allThreats =>
      _devices.where((d) => d.threatLevel != ThreatLevel.SAFE).toList();

  int get totalThreatsCount => allThreats.length;

  ScannerService() {
    // Populate with baseline initial scan state for seamless 2026 UX
    _seedInitialDevices();
  }

  void _seedInitialDevices() {
    final now = DateTime.now();
    _devices = [
      RFDevice(
        id: 'dev_covert_cam_01',
        macAddress: 'B4:E6:2D:4F:11:8A',
        name: 'Covert_HD_Stream_04',
        protocol: ProtocolType.WIFI,
        rssi: -42,
        channel: 6,
        frequencyMhz: 2437,
        isHidden: true,
        vendor: 'Espressif Systems',
        threatScore: 92,
        threatLevel: ThreatLevel.CRITICAL,
        threatReasons: [
          'SSID nascosto con streaming RTSP attivo',
          'Vendor associato a microcontrollori IoT stealth (ESP32-CAM)',
          'Prossimità critica: RSSI elevatissimo (-42 dBm) a meno di 1 metro',
        ],
        estimatedDistanceMeters: 0.8,
        firstSeen: now.subtract(const Duration(minutes: 4)),
        lastSeen: now,
        bearingAngle: 45.0,
      ),
      RFDevice(
        id: 'dev_covert_mic_02',
        macAddress: 'DC:A6:32:8B:19:EC',
        name: 'MiniAudio_Tx_V3',
        protocol: ProtocolType.BLE,
        rssi: -49,
        channel: 38,
        frequencyMhz: 2426,
        isHidden: false,
        vendor: 'Raspberry Pi Foundation',
        threatScore: 84,
        threatLevel: ThreatLevel.HIGH,
        threatReasons: [
          'Beacon BLE continuo non associabile a dispositivi noti',
          'Payload GATT contenente stream microfonico PCM raw',
          'Distanza stimata inferiore a 2 metri dal tavolo riunioni',
        ],
        estimatedDistanceMeters: 1.5,
        firstSeen: now.subtract(const Duration(minutes: 10)),
        lastSeen: now,
        bearingAngle: 135.0,
      ),
      RFDevice(
        id: 'dev_suspicious_plug_03',
        macAddress: '50:8A:06:AA:22:91',
        name: 'Smart_Socket_Internal',
        protocol: ProtocolType.WIFI,
        rssi: -64,
        channel: 1,
        frequencyMhz: 2412,
        isHidden: false,
        vendor: 'Tuya Smart Inc.',
        threatScore: 58,
        threatLevel: ThreatLevel.MEDIUM,
        threatReasons: [
          'Modulo Tuya integrato in lampada da tavolo',
          'Traffico anomalo verso endpoint cloud non autorizzato',
        ],
        estimatedDistanceMeters: 3.2,
        firstSeen: now.subtract(const Duration(minutes: 25)),
        lastSeen: now,
        bearingAngle: 220.0,
      ),
      RFDevice(
        id: 'dev_beacon_tracker_04',
        macAddress: '70:BC:10:99:34:F2',
        name: 'Tag_Tracker_Proximity',
        protocol: ProtocolType.BLE,
        rssi: -72,
        channel: 37,
        frequencyMhz: 2402,
        isHidden: false,
        vendor: 'Apple Inc.',
        threatScore: 35,
        threatLevel: ThreatLevel.LOW,
        threatReasons: [
          'Tag di tracciamento BLE rilevato nell\'ambiente per oltre 20 minuti',
        ],
        estimatedDistanceMeters: 4.8,
        firstSeen: now.subtract(const Duration(minutes: 30)),
        lastSeen: now,
        bearingAngle: 290.0,
      ),
      RFDevice(
        id: 'dev_safe_laptop_05',
        macAddress: 'F4:D4:88:51:77:01',
        name: 'Workstation_Dell_XPS',
        protocol: ProtocolType.WIFI,
        rssi: -58,
        channel: 36,
        frequencyMhz: 5180,
        isHidden: false,
        vendor: 'Intel Corporate',
        threatScore: 5,
        threatLevel: ThreatLevel.SAFE,
        threatReasons: [],
        estimatedDistanceMeters: 2.4,
        firstSeen: now.subtract(const Duration(hours: 1)),
        lastSeen: now,
        bearingAngle: 180.0,
      ),
      RFDevice(
        id: 'dev_safe_ap_06',
        macAddress: '00:1A:2B:3C:4D:5E',
        name: 'Corporate_Guest_WiFi',
        protocol: ProtocolType.WIFI,
        rssi: -78,
        channel: 48,
        frequencyMhz: 5240,
        isHidden: false,
        vendor: 'Cisco Systems',
        threatScore: 0,
        threatLevel: ThreatLevel.SAFE,
        threatReasons: [],
        estimatedDistanceMeters: 8.5,
        firstSeen: now.subtract(const Duration(hours: 2)),
        lastSeen: now,
        bearingAngle: 330.0,
      ),
    ];
  }

  void startScan() {
    if (_isScanning) return;
    _isScanning = true;
    _scanStartTime = DateTime.now();

    // Radar beam smooth rotation timer (~60 FPS)
    _radarAnimationTimer?.cancel();
    _radarAnimationTimer = Timer.periodic(const Duration(milliseconds: 33), (timer) {
      _radarAngle = (_radarAngle + 2.5) % 360.0;
      notifyListeners();
    });

    // Periodic RF sampling & jitter simulation
    _scanTimer?.cancel();
    _scanTimer = Timer.periodic(const Duration(milliseconds: 1800), (timer) {
      _simulateRfSample();
    });

    notifyListeners();
  }

  void stopScan() {
    _isScanning = false;
    _scanTimer?.cancel();
    _radarAnimationTimer?.cancel();
    notifyListeners();
  }

  void reset() {
    stopScan();
    _seedInitialDevices();
    _selectedGeigerTarget = null;
    notifyListeners();
  }

  void selectGeigerTarget(RFDevice? device) {
    _selectedGeigerTarget = device;
    _geigerTimer?.cancel();

    if (device != null) {
      _startGeigerFeedbackLoop(device);
    }
    notifyListeners();
  }

  void _startGeigerFeedbackLoop(RFDevice device) {
    // Determine interval based on RSSI:
    // RSSI -30 (very close) -> ~100ms
    // RSSI -90 (far) -> ~1200ms
    final clamped = device.rssi.clamp(-90, -30);
    final ratio = (clamped - (-90)) / (-30 - (-90)); // 0.0 to 1.0
    final intervalMs = (1200 - (ratio * 1050)).round().clamp(80, 1200);

    _geigerTimer = Timer.periodic(Duration(milliseconds: intervalMs), (timer) {
      if (_selectedGeigerTarget == null) {
        timer.cancel();
        return;
      }
      // Emit acoustic and haptic clicks
      if (ratio > 0.75) {
        HapticFeedback.heavyImpact();
      } else if (ratio > 0.4) {
        HapticFeedback.mediumImpact();
      } else {
        HapticFeedback.selectionClick();
      }
      SystemSound.play(SystemSoundType.click);
    });
  }

  void _simulateRfSample() {
    final rand = math.Random();
    final updated = _devices.map((device) {
      // Add realistic +-2 dBm RSSI fluctuations
      final delta = rand.nextInt(5) - 2;
      final newRssi = (device.rssi + delta).clamp(-95, -25);
      final newDistance = RFDevice.calculateDistance(newRssi);

      return device.copyWith(
        rssi: newRssi,
        estimatedDistanceMeters: newDistance,
        lastSeen: DateTime.now(),
      );
    }).toList();

    _devices = updated;
    if (_selectedGeigerTarget != null) {
      _selectedGeigerTarget = _devices.firstWhere(
        (d) => d.id == _selectedGeigerTarget!.id,
        orElse: () => _selectedGeigerTarget!,
      );
    }
    notifyListeners();
  }

  AuditReport generateAuditReport() {
    final now = DateTime.now();
    final summary = ScanSessionSummary(
      sessionId: 'SWEEP-${now.millisecondsSinceEpoch.toRadixString(16).toUpperCase()}',
      startedAt: _scanStartTime ?? now.subtract(const Duration(minutes: 15)),
      finishedAt: now,
      totalDevicesDetected: _devices.length,
      threatsDetected: totalThreatsCount,
      criticalThreats: criticalThreats.length,
      highThreats: highThreats.length,
      status: 'COMPLETED',
    );

    String clearance;
    if (criticalThreats.isNotEmpty) {
      clearance = 'AMBIENTE COMPROMESSO';
    } else if (highThreats.isNotEmpty || mediumThreats.isNotEmpty) {
      clearance = 'ATTENZIONE MINACCE RILEVATE';
    } else {
      clearance = 'AMBIENTE CERTIFICATO SICURO';
    }

    final recommendations = <String>[];
    if (criticalThreats.isNotEmpty) {
      recommendations.add(
        'ISPEZIONE FISICA IMMEDIATA: Rilevato stream RTSP occulto a meno di 1 metro. Controllare prese a muro, orologi e condotti aria.',
      );
      recommendations.add(
        'ISOLAMENTO RF: Attivare schermatura acustica e disalimentare le dorsali elettriche del perimetro indagato.',
      );
    }
    if (highThreats.isNotEmpty) {
      recommendations.add(
        'BONIFICA TAVOLO RIUNIONI: Localizzare il trasmettitore BLE sospetto (potenziale microfono spia) tramite il Tracker Geiger.',
      );
    }
    if (mediumThreats.isNotEmpty) {
      recommendations.add(
        'SEGNARE DISPOSITIVI IOT: Isolare la presa Smart Tuya su VLAN guest separata o rimuoverla dalla sala riservata.',
      );
    }
    if (recommendations.isEmpty) {
      recommendations.add('Nessuna anomalia RF riscontrata nel raggio operativo di 10 metri.');
      recommendations.add('Ripetere la bonifica periodica prima di ogni sessione a porte chiuse.');
    }

    return AuditReport(
      reportId: 'REP-${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}-001',
      generatedAt: now,
      summary: summary,
      flaggedDevices: allThreats,
      safetyClearance: clearance,
      recommendations: recommendations,
    );
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    _radarAnimationTimer?.cancel();
    _geigerTimer?.cancel();
    super.dispose();
  }
}
