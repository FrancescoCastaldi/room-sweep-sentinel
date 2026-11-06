import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../models/device_model.dart';
import 'ble_hardware_service.dart';

/// Operating modes for the RF counter-surveillance scanner
enum ScanMode {
  liveHardware,
  simulation,
}

/// ScannerService coordinates live BLE hardware scanning, real-time RF threat analysis,
/// Exponential Moving Average (EMA) signal smoothing, and simulated counter-surveillance sweeps.
class ScannerService extends ChangeNotifier {
  final BleHardwareService _bleService = BleHardwareService();

  ScanMode _scanMode = ScanMode.liveHardware;
  bool _isScanning = false;
  String? _statusMessage;

  // Primary device registry: keyed by unique device ID (MAC or BLE UUID)
  final Map<String, RFDevice> _devicesMap = {};
  List<RFDevice> _devices = [];

  // EMA RSSI tracking map: Device ID -> smoothed double value
  final Map<String, double> _emaRssiMap = {};

  // Smoothing parameter (Oracle specification: alpha = 0.30)
  // High enough to track room movement, low enough to discard multipath RF bounce
  static const double _emaAlpha = 0.30;

  RFDevice? _selectedGeigerTarget;
  DateTime? _scanStartTime;

  // Radar beam rotation decoupled from UI build storm:
  // Uses dedicated ValueNotifier so only the radar painter repaints at 60 FPS
  final ValueNotifier<double> radarAngleNotifier = ValueNotifier<double>(0.0);
  Timer? _radarAnimationTimer;

  // BLE batch throttling timer (~3.3 Hz / 300ms) to prevent UI rebuild storms
  Timer? _batchNotifyTimer;
  bool _hasPendingBatch = false;

  // Simulation sample timer
  Timer? _simulationTimer;

  // Subscriptions
  StreamSubscription<BleDevicePacket>? _blePacketSub;
  StreamSubscription<BleScanStatus>? _bleStatusSub;

  // Getters
  bool get isScanning => _isScanning;
  ScanMode get scanMode => _scanMode;
  bool get isLiveHardware => _scanMode == ScanMode.liveHardware;
  String? get statusMessage => _statusMessage;
  List<RFDevice> get devices => List.unmodifiable(_devices);
  RFDevice? get selectedGeigerTarget => _selectedGeigerTarget;
  double get radarAngle => radarAngleNotifier.value;
  DateTime? get scanStartTime => _scanStartTime;
  BleScanStatus get bleHardwareStatus => _bleService.status;

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
    _seedInitialDevices();
    _initBleStatusListener();
  }

  void _initBleStatusListener() {
    _bleStatusSub = _bleService.statusStream.listen((status) {
      if (status == BleScanStatus.bluetoothDisabled && _isScanning) {
        _statusMessage = 'Bluetooth disattivato durante la scansione.';
        notifyListeners();
      } else if (status == BleScanStatus.permissionDenied) {
        _statusMessage = 'Permessi Bluetooth/Posizione negati.';
        notifyListeners();
      }
    });
  }

  /// Populates baseline environment targets (Wi-Fi access points and known network targets)
  void _seedInitialDevices() {
    final now = DateTime.now();
    final initialList = [
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
          'Prossimità critica: RSSI elevato (-42 dBm) a meno di 1 metro',
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

    _devicesMap.clear();
    _emaRssiMap.clear();
    for (final d in initialList) {
      _devicesMap[d.id] = d;
      _emaRssiMap[d.id] = d.rssi.toDouble();
    }
    _syncDevicesList();
  }

  void _syncDevicesList() {
    final list = _devicesMap.values.toList();
    // Sort so threats appear at the top of lists and radars
    list.sort((a, b) => b.threatScore.compareTo(a.threatScore));
    _devices = list;

    // Keep Geiger target synchronized with latest RSSI/distance
    if (_selectedGeigerTarget != null) {
      _selectedGeigerTarget = _devicesMap[_selectedGeigerTarget!.id] ?? _selectedGeigerTarget;
    }
  }

  /// Toggles between live BLE hardware scanning and simulated RF sweeps
  void setScanMode(ScanMode mode) {
    if (_scanMode == mode) return;
    _scanMode = mode;
    _statusMessage = mode == ScanMode.liveHardware
        ? 'Modalità BLE Hardware Live attivata'
        : 'Modalità Simulazione attivata';

    if (_isScanning) {
      // Re-initialize scan under new mode
      stopScan();
      startScan();
    } else {
      notifyListeners();
    }
  }

  /// Starts counter-surveillance sweep
  Future<void> startScan() async {
    if (_isScanning) return;
    _isScanning = true;
    _scanStartTime = DateTime.now();
    _statusMessage = null;

    // 1. Start smooth 60 FPS radar sweep beam (isolated via ValueNotifier)
    _startRadarBeamAnimation();

    // 2. Start batch throttling timer (~3.3 Hz / 300ms) for UI stability
    _startBatchThrottleTimer();

    // 3. Initiate scanning based on active mode with fallback logic
    if (_scanMode == ScanMode.liveHardware) {
      try {
        final started = await _bleService.startScan();
        if (started) {
          _listenToBlePackets();
        } else {
          _fallbackToSimulation(
            reason: 'Hardware BLE non pronto o permessi mancanti. Attivata simulazione automatica.',
          );
        }
      } catch (e) {
        _fallbackToSimulation(
          reason: 'Errore avvio BLE ($e). Attivata modalità simulazione.',
        );
      }
    } else {
      _startSimulationLoop();
    }

    notifyListeners();
  }

  /// Fallback to simulation mode if hardware is unavailable
  void _fallbackToSimulation({required String reason}) {
    _scanMode = ScanMode.simulation;
    _statusMessage = reason;
    debugPrint('[ScannerService] Fallback: $reason');
    _startSimulationLoop();
    notifyListeners();
  }

  /// Subscribes to parsed BLE packets emitted by BleHardwareService
  void _listenToBlePackets() {
    _blePacketSub?.cancel();
    _blePacketSub = _bleService.packetStream.listen(
      (packet) {
        _processBlePacket(packet);
      },
      onError: (err) {
        debugPrint('[ScannerService] BLE stream error: $err');
      },
    );
  }

  /// Processes incoming packet with packet validation, cold-start handling,
  /// EMA RSSI smoothing, and threat heuristic mapping
  void _processBlePacket(BleDevicePacket packet) {
    final rawRssi = packet.rssi;

    // Filter invalid / anomalous RF packets (Oracle spec: rawRssi >= 0 or rawRssi < -110)
    if (rawRssi >= 0 || rawRssi < -110) {
      return;
    }

    final id = packet.remoteId;
    final now = DateTime.now();

    // Exponential Moving Average (EMA) with cold-start seeding
    double smoothedRssi;
    if (!_emaRssiMap.containsKey(id)) {
      // Cold start: seed with current raw packet RSSI
      smoothedRssi = rawRssi.toDouble();
    } else {
      final prevSmoothed = _emaRssiMap[id]!;
      smoothedRssi = (_emaAlpha * rawRssi) + ((1.0 - _emaAlpha) * prevSmoothed);
    }
    _emaRssiMap[id] = smoothedRssi;

    final finalRssi = smoothedRssi.round();
    final distanceMeters = RFDevice.calculateDistance(finalRssi);

    // Analyze threat profile from advertisement data, manufacturer ID, and service UUIDs
    final threatProfile = _analyzeThreatProfile(packet);

    final existing = _devicesMap[id];
    final device = RFDevice(
      id: id,
      macAddress: packet.remoteId,
      name: threatProfile.resolvedName.isNotEmpty ? threatProfile.resolvedName : packet.deviceName,
      protocol: ProtocolType.BLE,
      rssi: finalRssi,
      vendor: threatProfile.vendor,
      threatScore: threatProfile.threatScore,
      threatLevel: threatProfile.threatLevel,
      threatReasons: threatProfile.threatReasons,
      estimatedDistanceMeters: distanceMeters,
      firstSeen: existing?.firstSeen ?? now,
      lastSeen: now,
      bearingAngle: existing?.bearingAngle ?? RFDevice.deriveBearingFromMac(packet.remoteId),
    );

    _devicesMap[id] = device;
    _hasPendingBatch = true;
  }

  /// Threat heuristic classification engine for BLE beacons and IoT microcontrollers
  _BleThreatProfile _analyzeThreatProfile(BleDevicePacket packet) {
    final mfg = packet.manufacturerData;
    final uuids = packet.serviceUuids;
    final nameUpper = packet.deviceName.toUpperCase();
    final macClean = packet.remoteId.toUpperCase();

    int threatScore = 0;
    ThreatLevel threatLevel = ThreatLevel.SAFE;
    final reasons = <String>[];
    String vendor = 'Sconosciuto';
    String resolvedName = packet.deviceName;

    // 1. Apple AirTag / FindMy Network (Company Identifier 0x004C)
    if (mfg.containsKey(0x004C)) {
      final data = mfg[0x004C] ?? [];
      vendor = 'Apple Inc.';

      // Subtype 0x12 indicates offline finding / FindMy Network accessory (AirTag)
      if (data.isNotEmpty && data[0] == 0x12) {
        vendor = 'Apple Inc. (FindMy Network)';
        resolvedName = 'Apple FindMy / AirTag Tracker';
        threatScore = 75;
        threatLevel = ThreatLevel.HIGH;
        reasons.add('Dispositivo di tracciamento Apple AirTag / FindMy rilevato');
        reasons.add('Possibile pedinamento o geolocalizzazione clandestina nell\'ambiente');
      } else if (data.length >= 2 && data[0] == 0x02 && data[1] == 0x15) {
        // iBeacon frame format: 0x02, 0x15
        vendor = 'Apple Inc. (iBeacon)';
        resolvedName = 'Apple iBeacon Proximity';
        threatScore = 40;
        threatLevel = ThreatLevel.LOW;
        reasons.add('Beacon di prossimità commerciale iBeacon attivo');
      } else {
        threatScore = 15;
        threatLevel = ThreatLevel.SAFE;
      }
    }

    // 2. Tile Tracker (Company ID 0x00C7 or Service UUID 0xFEED)
    final hasTileUuid = uuids.any((u) => u.contains('feed'));
    if (mfg.containsKey(0x00C7) || hasTileUuid) {
      vendor = 'Tile Inc.';
      resolvedName = 'Tile Proximity Tracker';
      threatScore = 70;
      threatLevel = ThreatLevel.HIGH;
      reasons.add('Tag perimetrale Tile individuato (Company 0x00C7 / UUID 0xFEED)');
      reasons.add('Possibile localizzatore occultato per sorveglianza continuativa');
    }

    // 3. Tuya Smart devices (Company ID 0x07D7 or UUID 0xFD50 / 0xA201 or name patterns)
    final hasTuyaUuid = uuids.any((u) => u.contains('fd50') || u.contains('a201'));
    final hasTuyaName = nameUpper.contains('TUYA') ||
        nameUpper.contains('SMARTLIFE') ||
        nameUpper.contains('SMART_SOCKET') ||
        nameUpper.contains('SMART PLUG');
    if (mfg.containsKey(0x07D7) || hasTuyaUuid || hasTuyaName) {
      vendor = 'Tuya Smart Inc.';
      threatScore = math.max(threatScore, 58);
      if (threatLevel.severityOrder < ThreatLevel.MEDIUM.severityOrder) {
        threatLevel = ThreatLevel.MEDIUM;
      }
      reasons.add('Dispositivo IoT Tuya Smart identificato nell\'ambiente');
      reasons.add('Microcontroller commerciale con potenziale esfiltrazione cloud non verificata');
    }

    // 4. Espressif ESP32 / ESP8266 IoT chips (Company ID 0x02E5 or Espressif OUIs / names)
    final isEspressifMfg = mfg.containsKey(0x02E5);
    final isEspressifName = nameUpper.contains('ESP32') ||
        nameUpper.contains('ESP8266') ||
        nameUpper.contains('ESP_') ||
        nameUpper.contains('ESP-') ||
        nameUpper.contains('PROV_');
    final isEspressifMac = _isEspressifMacOUI(macClean);

    if (isEspressifMfg || isEspressifName || isEspressifMac) {
      vendor = 'Espressif Systems';
      threatScore = math.max(threatScore, 92);
      threatLevel = ThreatLevel.CRITICAL;
      reasons.add('Modulo microcontrollore Espressif (ESP32/ESP8266) attivo');
      reasons.add('Architettura tipica di microcamere stealth (ESP32-CAM) o microspie audio raw');
      reasons.add('Elevato rischio di canale di esfiltrazione Wi-Fi/BLE clandestino');
    }

    // 5. Covert name patterns (CAM, MIC, SPY, BUG, STREAM, MINI, etc.)
    const covertKeywords = [
      'CAM', 'MIC', 'SPY', 'BUG', 'STREAM', 'MINI',
      'AUDIO', 'COVERT', 'HIDDEN', 'CCTV', 'DVR',
      'NVR', 'WIRE', 'RECORD', 'SURVEILLANCE',
    ];

    for (final kw in covertKeywords) {
      if (nameUpper.contains(kw)) {
        threatScore = math.max(threatScore, 88);
        if (threatLevel.severityOrder < ThreatLevel.HIGH.severityOrder) {
          threatLevel = ThreatLevel.HIGH;
        }
        reasons.add('Nome identificativo broadcast contiene pattern sospetto ($kw)');
        reasons.add('Corrispondenza ad apparato di intercettazione occulto o microcamera');
        break;
      }
    }

    return _BleThreatProfile(
      vendor: vendor,
      resolvedName: resolvedName,
      threatScore: threatScore,
      threatLevel: threatLevel,
      threatReasons: reasons,
    );
  }

  /// Validates known Espressif IEEE OUIs
  bool _isEspressifMacOUI(String mac) {
    const espOuis = [
      '24:0A:C4', '24:6F:28', '24:DC:C3', '30:AE:A4', '3C:61:05',
      '3C:71:BF', '40:22:D8', '40:91:51', '48:27:E2', '48:31:B7',
      '48:55:19', '4C:11:AE', '4C:75:25', '54:43:B2', '54:5A:A6',
      '5C:CF:7F', '60:01:94', '68:B6:B3', '68:C6:3A', '70:03:9F',
      '70:B8:F6', '78:21:84', '78:E3:6D', '7C:DF:A1', '84:0D:8E',
      '84:CC:A8', '84:F7:03', '8C:AA:B5', '90:38:0C', '94:B5:55',
      '94:B9:7E', '94:E6:86', 'A0:20:A6', 'A0:76:4E', 'A0:B7:65',
      'A4:7B:9D', 'A4:CF:12', 'A4:E5:7C', 'A8:42:E3', 'A8:48:FA',
      'AC:67:B2', 'B4:E6:2D', 'BC:DD:C2', 'C4:4F:33', 'C4:DD:57',
      'C8:2E:18', 'CC:50:E3', 'D8:A0:1D', 'DC:4F:22', 'DC:54:75',
      'E0:98:06', 'E8:31:CD', 'E8:6B:EA', 'E8:9F:6D', 'E8:DB:84',
      'EC:62:60', 'EC:64:C9', 'EC:94:CB', 'F0:08:D1', 'F4:CF:A2',
    ];

    for (final prefix in espOuis) {
      if (mac.startsWith(prefix)) return true;
    }
    return false;
  }

  /// Isolated radar angle rotation timer (~60 FPS) that updates only [radarAngleNotifier]
  /// Decoupled from ScannerService.notifyListeners() to avoid UI rebuild storms
  void _startRadarBeamAnimation() {
    _radarAnimationTimer?.cancel();
    _radarAnimationTimer = Timer.periodic(const Duration(milliseconds: 33), (timer) {
      radarAngleNotifier.value = (radarAngleNotifier.value + 2.5) % 360.0;
    });
  }

  /// Throttles UI notifications to ~3.3 Hz (300ms buffer) to preserve 60 FPS UI performance
  void _startBatchThrottleTimer() {
    _batchNotifyTimer?.cancel();
    _batchNotifyTimer = Timer.periodic(const Duration(milliseconds: 300), (timer) {
      if (_hasPendingBatch) {
        _syncDevicesList();
        _hasPendingBatch = false;
        notifyListeners();
      }
    });
  }

  /// Simulation loop for testing and fallback mode
  void _startSimulationLoop() {
    _simulationTimer?.cancel();
    _simulationTimer = Timer.periodic(const Duration(milliseconds: 1800), (timer) {
      _simulateRfSample();
    });
  }

  void _simulateRfSample() {
    final rand = math.Random();
    for (final key in _devicesMap.keys) {
      final device = _devicesMap[key]!;
      final delta = rand.nextInt(5) - 2;
      final rawRssi = (device.rssi + delta).clamp(-95, -25);

      // Apply EMA
      final prevSmoothed = _emaRssiMap[device.id] ?? rawRssi.toDouble();
      final smoothed = (_emaAlpha * rawRssi) + ((1.0 - _emaAlpha) * prevSmoothed);
      _emaRssiMap[device.id] = smoothed;

      final finalRssi = smoothed.round();
      final newDistance = RFDevice.calculateDistance(finalRssi);

      _devicesMap[key] = device.copyWith(
        rssi: finalRssi,
        estimatedDistanceMeters: newDistance,
        lastSeen: DateTime.now(),
      );
    }
    _syncDevicesList();
    notifyListeners();
  }

  /// Stops counter-surveillance sweep
  Future<void> stopScan() async {
    _isScanning = false;
    _radarAnimationTimer?.cancel();
    _batchNotifyTimer?.cancel();
    _simulationTimer?.cancel();
    await _blePacketSub?.cancel();
    _blePacketSub = null;

    if (_scanMode == ScanMode.liveHardware) {
      await _bleService.stopScan();
    }

    notifyListeners();
  }

  /// Resets scan state back to initial baseline
  void reset() {
    stopScan();
    _seedInitialDevices();
    _selectedGeigerTarget = null;
    notifyListeners();
  }

  /// Selects target device for Geiger acoustic/tactile tracking
  void selectGeigerTarget(RFDevice? device) {
    _selectedGeigerTarget = device;
    notifyListeners();
  }

  /// Generates formal NIS2 compliance and RF counter-surveillance audit report
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
        'ISPEZIONE FISICA IMMEDIATA: Rilevato stream RTSP o chip Espressif occulto a breve distanza. Controllare prese a muro, orologi e condotti aria.',
      );
      recommendations.add(
        'ISOLAMENTO RF: Attivare schermatura acustica e disalimentare le dorsali elettriche del perimetro indagato.',
      );
    }
    if (highThreats.isNotEmpty) {
      recommendations.add(
        'BONIFICA TAVOLO RIUNIONI: Localizzare il trasmettitore BLE o tracker sospetto tramite il Tracker Geiger acustico.',
      );
    }
    if (mediumThreats.isNotEmpty) {
      recommendations.add(
        'SEGNARE DISPOSITIVI IOT: Isolare apparati smart home o moduli Tuya su VLAN guest dedicata.',
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
    _radarAnimationTimer?.cancel();
    _batchNotifyTimer?.cancel();
    _simulationTimer?.cancel();
    _blePacketSub?.cancel();
    _bleStatusSub?.cancel();
    radarAngleNotifier.dispose();
    _bleService.dispose();
    super.dispose();
  }
}

class _BleThreatProfile {
  final String vendor;
  final String resolvedName;
  final int threatScore;
  final ThreatLevel threatLevel;
  final List<String> threatReasons;

  const _BleThreatProfile({
    required this.vendor,
    required this.resolvedName,
    required this.threatScore,
    required this.threatLevel,
    required this.threatReasons,
  });
}
