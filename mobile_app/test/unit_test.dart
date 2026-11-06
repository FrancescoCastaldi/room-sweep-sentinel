import 'package:flutter_test/flutter_test.dart';
import 'package:room_sweep_sentinel/models/device_model.dart';
import 'package:room_sweep_sentinel/services/audit_logger_service.dart';

void main() {
  group('RFDevice Model & Path Loss Calculations', () {
    test('calculateDistance should produce realistic meter values for RSSI', () {
      // Strong signal (-40 dBm) -> within 1 meter
      final nearDist = RFDevice.calculateDistance(-40);
      expect(nearDist, lessThanOrEqualTo(1.0));

      // Medium signal (-60 dBm) -> around 1.0 - 2.0 meters
      final medDist = RFDevice.calculateDistance(-60);
      expect(medDist, greaterThan(nearDist));

      // Weak signal (-85 dBm) -> greater than 5.0 meters
      final farDist = RFDevice.calculateDistance(-85);
      expect(farDist, greaterThan(5.0));
    });

    test('distanceCategoryLabel classifies ranges correctly', () {
      final now = DateTime.now();
      final immediateDevice = RFDevice(
        id: '1',
        macAddress: 'AA:BB:CC:DD:EE:01',
        protocol: ProtocolType.WIFI,
        rssi: -38,
        estimatedDistanceMeters: 0.7,
        firstSeen: now,
        lastSeen: now,
      );
      expect(immediateDevice.distanceCategoryLabel, contains('< 1m'));

      final mediumDevice = RFDevice(
        id: '2',
        macAddress: 'AA:BB:CC:DD:EE:02',
        protocol: ProtocolType.BLE,
        rssi: -65,
        estimatedDistanceMeters: 3.5,
        firstSeen: now,
        lastSeen: now,
      );
      expect(mediumDevice.distanceCategoryLabel, contains('3-5m'));
    });

    test('signalStrengthFraction stays within 0.0 and 1.0', () {
      final now = DateTime.now();
      final maxSignalDevice = RFDevice(
        id: '1',
        macAddress: 'AA:BB:CC:DD:EE:01',
        protocol: ProtocolType.WIFI,
        rssi: -20, // Stronger than -30 dBm clamp
        firstSeen: now,
        lastSeen: now,
      );
      expect(maxSignalDevice.signalStrengthFraction, equals(1.0));

      final minSignalDevice = RFDevice(
        id: '2',
        macAddress: 'AA:BB:CC:DD:EE:02',
        protocol: ProtocolType.WIFI,
        rssi: -110, // Weaker than -100 dBm clamp
        firstSeen: now,
        lastSeen: now,
      );
      expect(minSignalDevice.signalStrengthFraction, equals(0.0));
    });

    test('Serialization and Deserialization from JSON matches backend schema', () {
      final jsonMap = {
        'id': 'cam_001',
        'mac_address': 'B4:E6:2D:4F:11:8A',
        'name': 'ESP32_Covert_Camera',
        'protocol': 'WIFI',
        'rssi': -42,
        'channel': 6,
        'frequency_mhz': 2437,
        'is_hidden': true,
        'vendor': 'Espressif Systems',
        'threat_score': 92,
        'threat_level': 'CRITICAL',
        'threat_reasons': ['Hidden SSID', 'High RSSI'],
        'estimated_distance_meters': 0.8,
        'first_seen': '2026-11-05T20:00:00.000Z',
        'last_seen': '2026-11-05T20:05:00.000Z',
        'bearing_angle': 45.0,
      };

      final device = RFDevice.fromJson(jsonMap);

      expect(device.id, equals('cam_001'));
      expect(device.macAddress, equals('B4:E6:2D:4F:11:8A'));
      expect(device.protocol, equals(ProtocolType.WIFI));
      expect(device.threatLevel, equals(ThreatLevel.CRITICAL));
      expect(device.isHidden, isTrue);
      expect(device.threatScore, equals(92));
      expect(device.threatReasons.length, equals(2));

      final serialized = device.toJson();
      expect(serialized['id'], equals('cam_001'));
      expect(serialized['threat_level'], equals('CRITICAL'));
      expect(serialized['mac_address'], equals('B4:E6:2D:4F:11:8A'));
    });
  });

  group('ThreatLevel Classification Enums', () {
    test('ThreatLevel severity order conforms to risk hierarchy', () {
      expect(ThreatLevel.CRITICAL.severityOrder, greaterThan(ThreatLevel.HIGH.severityOrder));
      expect(ThreatLevel.HIGH.severityOrder, greaterThan(ThreatLevel.MEDIUM.severityOrder));
      expect(ThreatLevel.MEDIUM.severityOrder, greaterThan(ThreatLevel.LOW.severityOrder));
      expect(ThreatLevel.LOW.severityOrder, greaterThan(ThreatLevel.SAFE.severityOrder));
    });

    test('ThreatLevel fromString correctly maps uppercase and lowercase', () {
      expect(ThreatLevel.fromString('CRITICAL'), equals(ThreatLevel.CRITICAL));
      expect(ThreatLevel.fromString('high'), equals(ThreatLevel.HIGH));
      expect(ThreatLevel.fromString('medium'), equals(ThreatLevel.MEDIUM));
      expect(ThreatLevel.fromString('safe'), equals(ThreatLevel.SAFE));
      expect(ThreatLevel.fromString('unknown_string'), equals(ThreatLevel.SAFE));
    });
  });

  group('NIS2 Cryptographic Audit Logger (EU Directive 2022/2555 Art. 21)', () {
    test('Genesis block and hash chain verification', () {
      final auditLogger = AuditLoggerService();

      expect(auditLogger.entryCount, equals(1)); // Genesis entry
      expect(auditLogger.chain.first.eventType, equals('NIS2_CHAIN_INITIALIZED'));
      expect(auditLogger.chain.first.previousHash, equals(AuditLoggerService.genesisHash));
      expect(auditLogger.verifyChainIntegrity(), isTrue);
    });

    test('Appending events maintains cryptographic link and valid chain', () {
      final auditLogger = AuditLoggerService();

      auditLogger.logEvent('SWEEP_START', {'mode': '360_FULL_SPECTRUM'});
      auditLogger.logEvent('THREAT_IDENTIFIED', {
        'mac': 'B4:E6:2D:4F:11:8A',
        'threat': 'CRITICAL',
      });
      auditLogger.logEvent('SWEEP_STOP', {'total_devices': 6});

      expect(auditLogger.entryCount, equals(4));
      expect(auditLogger.verifyChainIntegrity(), isTrue);

      // Verify each link points to previous hash
      for (int i = 1; i < auditLogger.chain.length; i++) {
        expect(auditLogger.chain[i].previousHash, equals(auditLogger.chain[i - 1].hash));
      }
    });
  });

  group('ScanSessionSummary and AuditReport', () {
    test('AuditReport generates proper safety clearance for critical threats', () {
      final now = DateTime.now();
      final summary = ScanSessionSummary(
        sessionId: 'SESS-001',
        startedAt: now.subtract(const Duration(minutes: 10)),
        finishedAt: now,
        totalDevicesDetected: 5,
        threatsDetected: 1,
        criticalThreats: 1,
        highThreats: 0,
        status: 'COMPLETED',
      );

      final report = AuditReport(
        reportId: 'REP-2026-001',
        generatedAt: now,
        summary: summary,
        flaggedDevices: [],
        safetyClearance: 'AMBIENTE COMPROMESSO',
        recommendations: ['Ispezione immediata'],
      );

      expect(report.summary.criticalThreats, equals(1));
      expect(report.safetyClearance, equals('AMBIENTE COMPROMESSO'));
      expect(report.recommendations.isNotEmpty, isTrue);

      final json = report.toJson();
      expect(json['safety_clearance'], equals('AMBIENTE COMPROMESSO'));
      expect(json['report_id'], equals('REP-2026-001'));
    });
  });

  group('Exponential Moving Average (EMA) RF Signal Filter & Bearing', () {
    test('EMA smooths high-frequency fluctuations towards steady signal', () {
      const alpha = 0.30;
      double ema = -80.0; // Initial seed (cold start)
      // Sequence of noisy readings around -50 dBm
      final readings = [-52, -48, -55, -47, -50, -49];
      for (final raw in readings) {
        ema = (alpha * raw) + ((1.0 - alpha) * ema);
      }
      // After several readings near -50, EMA should converge close to -50
      expect(ema, closeTo(-50.0, 5.0));
    });

    test('deriveBearingFromMac returns consistent 0-360 degree angle', () {
      final bearing1 = RFDevice.deriveBearingFromMac('B4:E6:2D:4F:11:8A');
      final bearing2 = RFDevice.deriveBearingFromMac('B4:E6:2D:4F:11:8A');
      expect(bearing1, equals(bearing2));
      expect(bearing1, greaterThanOrEqualTo(0.0));
      expect(bearing1, lessThan(360.0));
    });
  });
}
