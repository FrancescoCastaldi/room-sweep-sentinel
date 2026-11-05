import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// Immutable audit record according to EU NIS2 Directive (Art. 21)
/// and ISO/IEC 27001 requirements for secure forensic event logging.
class AuditLogEntry {
  final int index;
  final DateTime timestamp;
  final String eventType;
  final Map<String, dynamic> payload;
  final String previousHash;
  final String hash;

  const AuditLogEntry({
    required this.index,
    required this.timestamp,
    required this.eventType,
    required this.payload,
    required this.previousHash,
    required this.hash,
  });

  static String calculateHash({
    required int index,
    required DateTime timestamp,
    required String eventType,
    required Map<String, dynamic> payload,
    required String previousHash,
  }) {
    final payloadString = jsonEncode(payload);
    final rawData = '$index|${timestamp.toIso8601String()}|$eventType|$payloadString|$previousHash';
    return sha256.convert(utf8.encode(rawData)).toString();
  }

  Map<String, dynamic> toJson() {
    return {
      'index': index,
      'timestamp': timestamp.toIso8601String(),
      'event_type': eventType,
      'payload': payload,
      'previous_hash': previousHash,
      'hash': hash,
    };
  }

  factory AuditLogEntry.fromJson(Map<String, dynamic> json) {
    return AuditLogEntry(
      index: json['index'] as int,
      timestamp: DateTime.parse(json['timestamp'] as String),
      eventType: json['event_type'] as String,
      payload: Map<String, dynamic>.from(json['payload'] as Map),
      previousHash: json['previous_hash'] as String,
      hash: json['hash'] as String,
    );
  }
}

/// AuditLoggerService maintains a locally sealed, tamper-evident cryptographic log
/// ensuring legal admissibility and technical compliance for security operations.
class AuditLoggerService extends ChangeNotifier {
  static const String genesisHash = '0000000000000000000000000000000000000000000000000000000000000000';
  final List<AuditLogEntry> _chain = [];

  List<AuditLogEntry> get chain => List.unmodifiable(_chain);
  int get entryCount => _chain.length;
  String get latestHash => _chain.isEmpty ? genesisHash : _chain.last.hash;

  AuditLoggerService() {
    _recordGenesis();
  }

  void _recordGenesis() {
    final now = DateTime.now();
    final hash = AuditLogEntry.calculateHash(
      index: 0,
      timestamp: now,
      eventType: 'NIS2_CHAIN_INITIALIZED',
      payload: {
        'standard': 'EU NIS2 Directive 2022/2555 Art. 21',
        'subsystem': 'Room Sweep Sentinel Local Engine',
        'integrity': 'SHA-256 Hash Chained',
      },
      previousHash: genesisHash,
    );

    _chain.add(AuditLogEntry(
      index: 0,
      timestamp: now,
      eventType: 'NIS2_CHAIN_INITIALIZED',
      payload: {
        'standard': 'EU NIS2 Directive 2022/2555 Art. 21',
        'subsystem': 'Room Sweep Sentinel Local Engine',
        'integrity': 'SHA-256 Hash Chained',
      },
      previousHash: genesisHash,
      hash: hash,
    ));
  }

  void logEvent(String eventType, Map<String, dynamic> payload) {
    final now = DateTime.now();
    final index = _chain.length;
    final prevHash = latestHash;

    final hash = AuditLogEntry.calculateHash(
      index: index,
      timestamp: now,
      eventType: eventType,
      payload: payload,
      previousHash: prevHash,
    );

    _chain.add(AuditLogEntry(
      index: index,
      timestamp: now,
      eventType: eventType,
      payload: payload,
      previousHash: prevHash,
      hash: hash,
    ));

    notifyListeners();
  }

  /// Verifies the cryptographic integrity of the full audit chain.
  /// Returns true if every block matches its recalculation and previous link.
  bool verifyChainIntegrity() {
    if (_chain.isEmpty) return false;

    for (int i = 0; i < _chain.length; i++) {
      final entry = _chain[i];

      // Check previous hash link
      final expectedPrev = i == 0 ? genesisHash : _chain[i - 1].hash;
      if (entry.previousHash != expectedPrev) {
        return false;
      }

      // Check current hash recalculation
      final calculatedHash = AuditLogEntry.calculateHash(
        index: entry.index,
        timestamp: entry.timestamp,
        eventType: entry.eventType,
        payload: entry.payload,
        previousHash: entry.previousHash,
      );

      if (entry.hash != calculatedHash) {
        return false;
      }
    }
    return true;
  }
}
