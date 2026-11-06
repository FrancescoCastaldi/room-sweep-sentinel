import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../models/device_model.dart';
import 'ble_hardware_service.dart';

/// ScannerService coordinates live BLE hardware scanning, real-time RF threat analysis,
/// adaptive dual-rate EMA signal smoothing, and body-shielding physical azimuth correlation.
class ScannerService extends ChangeNotifier {
  final BleHardwareService _bleService = BleHardwareService();

  bool _isScanning = false;
  String? _statusMessage;

  // Primary device registry: keyed by unique device ID (MAC or BLE UUID)
  final Map<String, RFDevice> _devicesMap = {};
  List<RFDevice> _devices = [];

  // EMA RSSI tracking map: Device ID -> smoothed double value
  final Map<String, double> _emaRssiMap = {};

  // Body-shielding azimuth tracking: Device ID -> peak RSSI and peak heading
  final Map<String, int> _peakRssiMap = {};
  final Map<String, double> _physicalAzimuthMap = {};

  double _phoneHeading = 0.0;

  RFDevice? _selectedGeigerTarget;
  DateTime? _scanStartTime;

  // Radar beam rotation decoupled from UI build storm:
  // Uses dedicated ValueNotifier so only the radar painter repaints at 60 FPS
  final ValueNotifier<double> radarAngleNotifier = ValueNotifier<double>(0.0);
  Timer? _radarAnimationTimer;

  // BLE batch throttling timer (~3.3 Hz / 300ms) to prevent UI rebuild storms
  Timer? _batchNotifyTimer;
  bool _hasPendingBatch = false;

  // Subscriptions
  StreamSubscription<BleDevicePacket>? _blePacketSub;
  StreamSubscription<BleScanStatus>? _bleStatusSub;

  // Getters
  bool get isScanning => _isScanning;
  String? get statusMessage => _statusMessage;
  List<RFDevice> get devices => List.unmodifiable(_devices);
  RFDevice? get selectedGeigerTarget => _selectedGeigerTarget;
  double get radarAngle => radarAngleNotifier.value;
  double get phoneHeading => _phoneHeading;
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
    _initBleStatusListener();
  }

  void _initBleStatusListener() {
    _bleStatusSub = _bleService.statusStream.listen((status) {
      if (status == BleScanStatus.bluetoothDisabled && _isScanning) {
        _statusMessage = 'Bluetooth disattivato. Attiva il Bluetooth sul telefono per scansionare.';
        notifyListeners();
      } else if (status == BleScanStatus.permissionDenied) {
        _statusMessage = 'Permessi Bluetooth/Posizione negati. Concedili nelle impostazioni.';
        notifyListeners();
      } else if (status == BleScanStatus.error) {
        _statusMessage = _bleService.errorMessage;
        notifyListeners();
      }
    });
  }

  /// Updates current phone compass heading (0° - 360°) to rotate radar & track peak azimuths
  void updatePhoneHeading(double heading) {
    _phoneHeading = heading;
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

  /// Starts live counter-surveillance sweep
  Future<void> startScan() async {
    if (_isScanning) return;
    _isScanning = true;
    _scanStartTime = DateTime.now();
    _statusMessage = null;

    // 1. Start smooth 60 FPS radar sweep beam (isolated via ValueNotifier)
    _startRadarBeamAnimation();

    // 2. Start batch throttling timer (~3.3 Hz / 300ms) for UI stability
    _startBatchThrottleTimer();

    // 3. Initiate native hardware scanning
    try {
      final started = await _bleService.startScan();
      if (started) {
        _listenToBlePackets();
        _statusMessage = null;
      } else {
        _statusMessage = _bleService.errorMessage ??
            'Scansione non avviata. Verifica che Bluetooth e Posizione (GPS) siano attivi sul telefono.';
      }
    } catch (e) {
      _statusMessage = 'Errore antenna BLE: $e';
    }

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

  /// Processes incoming packet with packet validation, adaptive fast-attack smoothing,
  /// body-shielding peak heading correlation, and threat heuristic mapping
  void _processBlePacket(BleDevicePacket packet) {
    final rawRssi = packet.rssi;

    // Filter invalid / anomalous RF packets
    if (rawRssi >= 0 || rawRssi < -110) {
      return;
    }

    final id = packet.remoteId;
    final now = DateTime.now();

    // 1. Adaptive Fast-Attack / Slow-Decay RSSI smoothing (Directive B)
    double smoothedRssi;
    if (!_emaRssiMap.containsKey(id)) {
      // Cold start: instantaneous seed
      smoothedRssi = rawRssi.toDouble();
    } else {
      smoothedRssi = RFDevice.calculateAdaptiveRssi(_emaRssiMap[id]!, rawRssi);
    }
    _emaRssiMap[id] = smoothedRssi;

    final finalRssi = smoothedRssi.round();

    // 2. Calibrated 1-meter TxPower and Path Loss Calculation (n = 2.2)
    int txPowerAt1m = -59;
    if (packet.txPowerLevel != null && packet.txPowerLevel! >= -40 && packet.txPowerLevel! <= -10) {
      txPowerAt1m = packet.txPowerLevel! - 41;
    }
    final distanceMeters = RFDevice.calculateDistance(finalRssi, txPowerAt1m: txPowerAt1m);

    // 3. Body-Shielding Azimuth Tracking (Directive C):
    // Correlates phone compass heading with peak RSSI sector to determine physical direction
    double azimuth;
    final prevPeak = _peakRssiMap[id] ?? -120;
    if (finalRssi > prevPeak || !_physicalAzimuthMap.containsKey(id)) {
      _peakRssiMap[id] = finalRssi;
      _physicalAzimuthMap[id] = _phoneHeading;
      azimuth = _phoneHeading;
    } else if (finalRssi >= prevPeak - 3) {
      // Near peak sector: smooth bearing towards current heading
      final prevAzimuth = _physicalAzimuthMap[id] ?? _phoneHeading;
      final delta = ((_phoneHeading - prevAzimuth + 540.0) % 360.0) - 180.0;
      azimuth = (prevAzimuth + (delta * 0.25) + 360.0) % 360.0;
      _physicalAzimuthMap[id] = azimuth;
    } else {
      azimuth = _physicalAzimuthMap[id] ?? _phoneHeading;
    }

    // Analyze threat profile from advertisement data, manufacturer ID, and service UUIDs
    final threatProfile = _analyzeThreatProfile(packet);
    final existing = _devicesMap[id];

    final device = RFDevice(
      id: id,
      macAddress: packet.remoteId,
      name: (threatProfile.resolvedName.isNotEmpty && threatProfile.resolvedName != 'Dispositivo BLE sconosciuto')
          ? threatProfile.resolvedName
          : (packet.deviceName.isNotEmpty && packet.deviceName != 'Dispositivo BLE sconosciuto'
              ? packet.deviceName
              : 'Segnale BLE [${packet.remoteId.replaceAll(':', '').toUpperCase().padRight(4).substring(0, 4)}]'),
      protocol: ProtocolType.BLE,
      rssi: finalRssi,
      vendor: threatProfile.vendor,
      threatScore: threatProfile.threatScore,
      threatLevel: threatProfile.threatLevel,
      threatReasons: threatProfile.threatReasons,
      estimatedDistanceMeters: distanceMeters,
      firstSeen: existing?.firstSeen ?? now,
      lastSeen: now,
      bearingAngle: azimuth,
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
    String vendor = 'Dispositivo Periferico';
    String resolvedName = packet.deviceName;

    if (resolvedName.isEmpty || resolvedName == 'Dispositivo BLE sconosciuto') {
      final shortMac = macClean.length >= 8
          ? macClean.substring(macClean.length - 8)
          : macClean;
      resolvedName = 'Segnale BLE [$shortMac]';
    }

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
        vendor = 'Apple Inc.';
        resolvedName = 'Dispositivo Apple BLE';
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

  /// Stops counter-surveillance sweep
  Future<void> stopScan() async {
    _isScanning = false;
    _radarAnimationTimer?.cancel();
    _batchNotifyTimer?.cancel();
    await _blePacketSub?.cancel();
    _blePacketSub = null;

    await _bleService.stopScan();
    notifyListeners();
  }

  /// Resets scan state back to initial empty baseline
  void reset() {
    stopScan();
    _devicesMap.clear();
    _emaRssiMap.clear();
    _peakRssiMap.clear();
    _physicalAzimuthMap.clear();
    _syncDevicesList();
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

    final flagged = _devices.where((d) => d.threatLevel != ThreatLevel.SAFE).toList();

    String clearance;
    final recommendations = <String>[];

    if (criticalThreats.isNotEmpty) {
      clearance = 'AMBIENTE COMPROMESSO';
      recommendations.add(
        'Rilevati ${criticalThreats.length} apparati di livello CRITICO (microspie audio o telecamere occulte attive).',
      );
      recommendations.add(
        'Isolare immediatamente l\'area ed eseguire bonifica fisica su controsoffitti, prese elettriche e arredi.',
      );
    } else if (highThreats.isNotEmpty) {
      clearance = 'ATTENZIONE RICHIESTA';
      recommendations.add(
        'Rilevati apparati a rischio ELEVATO (tracker BLE o apparati non autorizzati).',
      );
      recommendations.add('Avviare il localizzatore acustico Geiger per localizzare le sorgenti.');
    } else if (mediumThreats.isNotEmpty) {
      clearance = 'POTENZIALE VULNERABILITÀ';
      recommendations.add('Rilevati dispositivi IoT commerciali non censiti nella whitelist aziendale.');
    } else {
      clearance = 'AMBIENTE BONIFICATO';
      recommendations.add('Nessuna trasmissione RF non autorizzata rilevata nel perimetro.');
      recommendations.add('Conforme alle direttive di sicurezza fisica per riunioni riservate.');
    }

    return AuditReport(
      reportId: 'REP-NIS2-${now.millisecondsSinceEpoch.toString().substring(5)}',
      generatedAt: now,
      summary: summary,
      flaggedDevices: flagged,
      safetyClearance: clearance,
      recommendations: recommendations,
    );
  }

  @override
  void dispose() {
    _radarAnimationTimer?.cancel();
    _batchNotifyTimer?.cancel();
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
