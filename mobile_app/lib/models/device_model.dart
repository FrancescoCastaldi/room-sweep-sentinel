import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

enum ProtocolType {
  WIFI,
  BLE;

  static ProtocolType fromString(String value) {
    return value.toUpperCase() == 'BLE' ? ProtocolType.BLE : ProtocolType.WIFI;
  }
}

enum ThreatLevel {
  SAFE,
  LOW,
  MEDIUM,
  HIGH,
  CRITICAL;

  static ThreatLevel fromString(String value) {
    switch (value.toUpperCase()) {
      case 'CRITICAL':
        return ThreatLevel.CRITICAL;
      case 'HIGH':
        return ThreatLevel.HIGH;
      case 'MEDIUM':
        return ThreatLevel.MEDIUM;
      case 'LOW':
        return ThreatLevel.LOW;
      case 'SAFE':
      default:
        return ThreatLevel.SAFE;
    }
  }

  Color get color {
    switch (this) {
      case ThreatLevel.CRITICAL:
        return AppColors.threatCritical;
      case ThreatLevel.HIGH:
        return AppColors.threatHigh;
      case ThreatLevel.MEDIUM:
        return AppColors.threatMedium;
      case ThreatLevel.LOW:
        return AppColors.threatLow;
      case ThreatLevel.SAFE:
        return AppColors.threatSafe;
    }
  }

  String get label {
    switch (this) {
      case ThreatLevel.CRITICAL:
        return 'CRITICO';
      case ThreatLevel.HIGH:
        return 'ALTO RISCHIO';
      case ThreatLevel.MEDIUM:
        return 'SOSPETTO';
      case ThreatLevel.LOW:
        return 'ATTENZIONE';
      case ThreatLevel.SAFE:
        return 'SICURO';
    }
  }

  IconData get icon {
    switch (this) {
      case ThreatLevel.CRITICAL:
        return Icons.warning_rounded;
      case ThreatLevel.HIGH:
        return Icons.error_outline_rounded;
      case ThreatLevel.MEDIUM:
        return Icons.policy_rounded;
      case ThreatLevel.LOW:
        return Icons.info_outline_rounded;
      case ThreatLevel.SAFE:
        return Icons.verified_user_rounded;
    }
  }

  int get severityOrder {
    switch (this) {
      case ThreatLevel.CRITICAL:
        return 5;
      case ThreatLevel.HIGH:
        return 4;
      case ThreatLevel.MEDIUM:
        return 3;
      case ThreatLevel.LOW:
        return 2;
      case ThreatLevel.SAFE:
        return 1;
    }
  }
}

class RFDevice {
  final String id;
  final String macAddress;
  final String name;
  final ProtocolType protocol;
  final int rssi;
  final int? channel;
  final int? frequencyMhz;
  final bool isHidden;
  final String vendor;
  final int threatScore;
  final ThreatLevel threatLevel;
  final List<String> threatReasons;
  final double estimatedDistanceMeters;
  final DateTime firstSeen;
  final DateTime lastSeen;
  final double bearingAngle; // in degrees: 0° (North) to 360°

  const RFDevice({
    required this.id,
    required this.macAddress,
    this.name = 'Dispositivo sconosciuto',
    required this.protocol,
    required this.rssi,
    this.channel,
    this.frequencyMhz,
    this.isHidden = false,
    this.vendor = 'Sconosciuto',
    this.threatScore = 0,
    this.threatLevel = ThreatLevel.SAFE,
    this.threatReasons = const [],
    this.estimatedDistanceMeters = 5.0,
    required this.firstSeen,
    required this.lastSeen,
    this.bearingAngle = 0.0,
  });

  /// Calculates log-distance path loss distance estimate
  /// RSSI = -10 * n * log10(d) + A
  static double calculateDistance(int rssi, {int txPowerAt1m = -59, double pathLossExponent = 2.4}) {
    if (rssi == 0) return -1.0;
    final ratio = (txPowerAt1m - rssi) / (10.0 * pathLossExponent);
    final distance = math.pow(10.0, ratio).toDouble();
    return double.parse(distance.toStringAsFixed(1));
  }

  /// Categorized human-readable distance range
  String get distanceCategoryLabel {
    if (estimatedDistanceMeters <= 1.0) {
      return 'Contatto Diretto (< 1m)';
    } else if (estimatedDistanceMeters <= 3.0) {
      return 'Prossimità Immediata (1-3m)';
    } else if (estimatedDistanceMeters <= 5.0) {
      return 'Raggio Medio (3-5m)';
    } else {
      return 'Perimetro Esterno (> 5m)';
    }
  }

  /// Normalized signal strength percentage for gauge rendering (0% to 100%)
  double get signalStrengthFraction {
    // Typical Wi-Fi/BLE RSSI ranges from -100 dBm (weak) to -30 dBm (strong)
    final clamped = rssi.clamp(-100, -30);
    return (clamped - (-100)) / (-30 - (-100));
  }

  RFDevice copyWith({
    String? id,
    String? macAddress,
    String? name,
    ProtocolType? protocol,
    int? rssi,
    int? channel,
    int? frequencyMhz,
    bool? isHidden,
    String? vendor,
    int? threatScore,
    ThreatLevel? threatLevel,
    List<String>? threatReasons,
    double? estimatedDistanceMeters,
    DateTime? firstSeen,
    DateTime? lastSeen,
    double? bearingAngle,
  }) {
    return RFDevice(
      id: id ?? this.id,
      macAddress: macAddress ?? this.macAddress,
      name: name ?? this.name,
      protocol: protocol ?? this.protocol,
      rssi: rssi ?? this.rssi,
      channel: channel ?? this.channel,
      frequencyMhz: frequencyMhz ?? this.frequencyMhz,
      isHidden: isHidden ?? this.isHidden,
      vendor: vendor ?? this.vendor,
      threatScore: threatScore ?? this.threatScore,
      threatLevel: threatLevel ?? this.threatLevel,
      threatReasons: threatReasons ?? this.threatReasons,
      estimatedDistanceMeters: estimatedDistanceMeters ?? this.estimatedDistanceMeters,
      firstSeen: firstSeen ?? this.firstSeen,
      lastSeen: lastSeen ?? this.lastSeen,
      bearingAngle: bearingAngle ?? this.bearingAngle,
    );
  }

  factory RFDevice.fromJson(Map<String, dynamic> json) {
    final rssiVal = (json['rssi'] as num?)?.toInt() ?? -70;
    final distVal = (json['estimated_distance_meters'] as num?)?.toDouble() ??
        RFDevice.calculateDistance(rssiVal);

    // If backend doesn't provide bearing_angle, deterministically derive it from MAC
    final bearing = (json['bearing_angle'] as num?)?.toDouble() ??
        _deriveBearingFromMac(json['mac_address'] as String? ?? '00:00:00:00:00:00');

    return RFDevice(
      id: json['id'] as String? ?? json['mac_address'] as String? ?? '',
      macAddress: json['mac_address'] as String? ?? '00:00:00:00:00:00',
      name: json['name'] as String? ?? 'Dispositivo sconosciuto',
      protocol: ProtocolType.fromString(json['protocol'] as String? ?? 'WIFI'),
      rssi: rssiVal,
      channel: (json['channel'] as num?)?.toInt(),
      frequencyMhz: (json['frequency_mhz'] as num?)?.toInt(),
      isHidden: json['is_hidden'] as bool? ?? false,
      vendor: json['vendor'] as String? ?? 'Sconosciuto',
      threatScore: (json['threat_score'] as num?)?.toInt() ?? 0,
      threatLevel: ThreatLevel.fromString(json['threat_level'] as String? ?? 'SAFE'),
      threatReasons: (json['threat_reasons'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      estimatedDistanceMeters: distVal,
      firstSeen: json['first_seen'] != null
          ? DateTime.tryParse(json['first_seen'] as String) ?? DateTime.now()
          : DateTime.now(),
      lastSeen: json['last_seen'] != null
          ? DateTime.tryParse(json['last_seen'] as String) ?? DateTime.now()
          : DateTime.now(),
      bearingAngle: bearing,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'mac_address': macAddress,
      'name': name,
      'protocol': protocol == ProtocolType.BLE ? 'BLE' : 'WIFI',
      'rssi': rssi,
      'channel': channel,
      'frequency_mhz': frequencyMhz,
      'is_hidden': isHidden,
      'vendor': vendor,
      'threat_score': threatScore,
      'threat_level': threatLevel.name,
      'threat_reasons': threatReasons,
      'estimated_distance_meters': estimatedDistanceMeters,
      'first_seen': firstSeen.toIso8601String(),
      'last_seen': lastSeen.toIso8601String(),
      'bearing_angle': bearingAngle,
    };
  }

  static double _deriveBearingFromMac(String mac) {
    final clean = mac.replaceAll(':', '');
    final hash = clean.runes.fold<int>(0, (prev, elem) => prev + elem);
    return (hash % 360).toDouble();
  }
}

class ScanSessionSummary {
  final String sessionId;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final int totalDevicesDetected;
  final int threatsDetected;
  final int criticalThreats;
  final int highThreats;
  final String status;

  const ScanSessionSummary({
    required this.sessionId,
    required this.startedAt,
    this.finishedAt,
    this.totalDevicesDetected = 0,
    this.threatsDetected = 0,
    this.criticalThreats = 0,
    this.highThreats = 0,
    this.status = 'IDLE',
  });

  factory ScanSessionSummary.fromJson(Map<String, dynamic> json) {
    return ScanSessionSummary(
      sessionId: json['session_id'] as String? ?? 'sess_0',
      startedAt: json['started_at'] != null
          ? DateTime.tryParse(json['started_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      finishedAt: json['finished_at'] != null
          ? DateTime.tryParse(json['finished_at'] as String)
          : null,
      totalDevicesDetected: (json['total_devices_detected'] as num?)?.toInt() ?? 0,
      threatsDetected: (json['threats_detected'] as num?)?.toInt() ?? 0,
      criticalThreats: (json['critical_threats'] as num?)?.toInt() ?? 0,
      highThreats: (json['high_threats'] as num?)?.toInt() ?? 0,
      status: json['status'] as String? ?? 'IDLE',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'session_id': sessionId,
      'started_at': startedAt.toIso8601String(),
      'finished_at': finishedAt?.toIso8601String(),
      'total_devices_detected': totalDevicesDetected,
      'threats_detected': threatsDetected,
      'critical_threats': criticalThreats,
      'high_threats': highThreats,
      'status': status,
    };
  }
}

class AuditReport {
  final String reportId;
  final DateTime generatedAt;
  final ScanSessionSummary summary;
  final List<RFDevice> flaggedDevices;
  final String safetyClearance; // "CERTIFICATO SICURO", "ATTENZIONE MINACCE", "AMBIENTE COMPROMESSO"
  final List<String> recommendations;

  const AuditReport({
    required this.reportId,
    required this.generatedAt,
    required this.summary,
    required this.flaggedDevices,
    required this.safetyClearance,
    required this.recommendations,
  });

  factory AuditReport.fromJson(Map<String, dynamic> json) {
    return AuditReport(
      reportId: json['report_id'] as String? ?? 'rep_0',
      generatedAt: json['generated_at'] != null
          ? DateTime.tryParse(json['generated_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      summary: json['summary'] != null
          ? ScanSessionSummary.fromJson(json['summary'] as Map<String, dynamic>)
          : ScanSessionSummary(sessionId: 'sess_default', startedAt: DateTime.now()),
      flaggedDevices: (json['flagged_devices'] as List<dynamic>?)
              ?.map((e) => RFDevice.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      safetyClearance: json['safety_clearance'] as String? ?? 'CERTIFICATO SICURO',
      recommendations: (json['recommendations'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'report_id': reportId,
      'generated_at': generatedAt.toIso8601String(),
      'summary': summary.toJson(),
      'flagged_devices': flaggedDevices.map((e) => e.toJson()).toList(),
      'safety_clearance': safetyClearance,
      'recommendations': recommendations,
    };
  }
}
