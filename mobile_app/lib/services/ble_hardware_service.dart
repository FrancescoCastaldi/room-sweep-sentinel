import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

/// Status states for Bluetooth Low Energy hardware operations
enum BleScanStatus {
  idle,
  checkingPermissions,
  permissionDenied,
  bluetoothDisabled,
  unsupported,
  scanning,
  error,
}

/// Unified, decoupled data model representing an incoming BLE advertisement packet
class BleDevicePacket {
  final String remoteId;
  final String deviceName;
  final int rssi;
  final int? txPowerLevel;
  final Map<int, List<int>> manufacturerData;
  final List<String> serviceUuids;
  final DateTime timestamp;
  final bool isConnectable;
  final ScanResult? rawScanResult;

  const BleDevicePacket({
    required this.remoteId,
    required this.deviceName,
    required this.rssi,
    this.txPowerLevel,
    this.manufacturerData = const {},
    this.serviceUuids = const [],
    required this.timestamp,
    this.isConnectable = false,
    this.rawScanResult,
  });

  /// Factory constructor to cleanly extract advertising metadata from FlutterBluePlus [ScanResult]
  factory BleDevicePacket.fromScanResult(ScanResult result) {
    String resolvedName = result.advertisementData.advName.trim();
    if (resolvedName.isEmpty) {
      resolvedName = result.device.platformName.trim();
    }
    if (resolvedName.isEmpty) {
      resolvedName = 'Dispositivo BLE sconosciuto';
    }

    return BleDevicePacket(
      remoteId: result.device.remoteId.str,
      deviceName: resolvedName,
      rssi: result.rssi,
      txPowerLevel: result.advertisementData.txPowerLevel,
      manufacturerData: result.advertisementData.manufacturerData,
      serviceUuids: result.advertisementData.serviceUuids
          .map((uuid) => uuid.str128.toLowerCase())
          .toList(),
      timestamp: result.timeStamp,
      isConnectable: result.advertisementData.connectable,
      rawScanResult: result,
    );
  }

  @override
  String toString() {
    return 'BleDevicePacket(id: $remoteId, name: $deviceName, rssi: $rssi, mfg: ${manufacturerData.keys.toList()})';
  }
}

/// BleHardwareService encapsulates flutter_blue_plus hardware operations,
/// runtime permissions lifecycle via permission_handler, and adapter state management.
class BleHardwareService {
  BleScanStatus _status = BleScanStatus.idle;
  String? _errorMessage;

  final StreamController<BleScanStatus> _statusController =
      StreamController<BleScanStatus>.broadcast();
  final StreamController<BleDevicePacket> _packetController =
      StreamController<BleDevicePacket>.broadcast();

  StreamSubscription<List<ScanResult>>? _scanResultsSub;
  StreamSubscription<BluetoothAdapterState>? _adapterStateSub;

  BleScanStatus get status => _status;
  String? get errorMessage => _errorMessage;
  Stream<BleScanStatus> get statusStream => _statusController.stream;
  Stream<BleDevicePacket> get packetStream => _packetController.stream;

  BleHardwareService() {
    _initAdapterMonitoring();
  }

  /// Observes hardware adapter state transitions (e.g. user toggling BT from quick settings)
  void _initAdapterMonitoring() {
    try {
      _adapterStateSub = FlutterBluePlus.adapterState.listen(
        (state) {
          if (state == BluetoothAdapterState.off) {
            if (_status == BleScanStatus.scanning) {
              _setStatus(BleScanStatus.bluetoothDisabled);
            }
          }
        },
        onError: (err) {
          debugPrint('[BleHardwareService] Adapter state listener error: $err');
        },
      );
    } catch (e) {
      debugPrint('[BleHardwareService] FlutterBluePlus init error: $e');
    }
  }

  void _setStatus(BleScanStatus newStatus, [String? errorMsg]) {
    _status = newStatus;
    _errorMessage = errorMsg;
    if (!_statusController.isClosed) {
      _statusController.add(newStatus);
    }
  }

  /// Verifies and requests required Android runtime permissions:
  /// - Android 12+ (API 31+): BLUETOOTH_SCAN, BLUETOOTH_CONNECT
  /// - Android <= 11 and Beacon Proximity: ACCESS_FINE_LOCATION
  Future<bool> checkAndRequestPermissions() async {
    _setStatus(BleScanStatus.checkingPermissions);

    try {
      if (Platform.isAndroid) {
        final permissions = [
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
          Permission.location,
        ];

        final statuses = await permissions.request();

        final scanGranted = statuses[Permission.bluetoothScan]?.isGranted ?? false;
        final connectGranted = statuses[Permission.bluetoothConnect]?.isGranted ?? false;
        final locationGranted = statuses[Permission.location]?.isGranted ?? false;

        // On Android, if Bluetooth Scan is granted (or location on older versions), we have at least one valid path
        final isPermitted = scanGranted || locationGranted;

        if (!isPermitted) {
          _setStatus(
            BleScanStatus.permissionDenied,
            'Permessi Bluetooth o Posizione negati. Concedi i permessi per rilevare dispositivi reali.',
          );
          return false;
        }

        // Check if GPS / Location Services are enabled on the device (Android requirement for BLE scan results)
        try {
          final locationServiceEnabled = await Permission.location.serviceStatus.isEnabled;
          if (!locationServiceEnabled) {
            debugPrint('[BleHardwareService] Warning: Location service (GPS) is disabled');
            _setStatus(
              BleScanStatus.error,
              'Attiva la Posizione (GPS) sul telefono per consentire ad Android di rilevare i segnali Bluetooth.',
            );
          }
        } catch (_) {}
      }
      return true;
    } catch (e) {
      debugPrint('[BleHardwareService] Permission request failed: $e');
      _setStatus(BleScanStatus.permissionDenied, e.toString());
      return false;
    }
  }

  /// Checks if device Bluetooth hardware is turned on, awaiting transition past 'unknown' state
  Future<bool> ensureBluetoothOn() async {
    try {
      final isSupported = await FlutterBluePlus.isSupported;
      if (!isSupported) {
        _setStatus(
          BleScanStatus.unsupported,
          'Il modulo Bluetooth Low Energy non è supportato su questo dispositivo.',
        );
        return false;
      }

      // Important: Wait past the initial 'unknown' adapter state emitted during native initialization
      BluetoothAdapterState state = await FlutterBluePlus.adapterState
          .where((s) => s != BluetoothAdapterState.unknown)
          .first
          .timeout(
            const Duration(seconds: 4),
            onTimeout: () => BluetoothAdapterState.off,
          );

      if (state != BluetoothAdapterState.on) {
        if (Platform.isAndroid) {
          try {
            await FlutterBluePlus.turnOn();
            // Await adapter transition to ON with a 4-second timeout
            state = await FlutterBluePlus.adapterState
                .firstWhere((s) => s == BluetoothAdapterState.on)
                .timeout(
                  const Duration(seconds: 4),
                  onTimeout: () => BluetoothAdapterState.off,
                );
          } catch (turnOnErr) {
            debugPrint('[BleHardwareService] FlutterBluePlus.turnOn error: $turnOnErr');
          }
        }

        if (state != BluetoothAdapterState.on) {
          _setStatus(
            BleScanStatus.bluetoothDisabled,
            'Bluetooth disattivato. Attiva il Bluetooth sul telefono per avviare la bonifica RF.',
          );
          return false;
        }
      }
      return true;
    } catch (e) {
      debugPrint('[BleHardwareService] ensureBluetoothOn error: $e');
      _setStatus(BleScanStatus.error, e.toString());
      return false;
    }
  }

  /// Starts continuous, low-latency BLE peripheral scanning
  Future<bool> startScan() async {
    try {
      final hasPermissions = await checkAndRequestPermissions();
      if (!hasPermissions) return false;

      final isBluetoothReady = await ensureBluetoothOn();
      if (!isBluetoothReady) return false;

      // Ensure any running scan is stopped before starting
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
      }

      // Cancel previous scan subscription if active
      await _scanResultsSub?.cancel();

      _setStatus(BleScanStatus.scanning);

      // Listen to cumulative scan results and emit parsed packets
      _scanResultsSub = FlutterBluePlus.scanResults.listen(
        (List<ScanResult> results) {
          for (final result in results) {
            if (!_packetController.isClosed) {
              _packetController.add(BleDevicePacket.fromScanResult(result));
            }
          }
        },
        onError: (err) {
          debugPrint('[BleHardwareService] Scan stream error: $err');
          _setStatus(BleScanStatus.error, err.toString());
        },
      );

      // Start continuous scanning with low latency mode and explicit fine location requirement
      await FlutterBluePlus.startScan(
        continuousUpdates: true,
        androidUsesFineLocation: true,
        androidScanMode: AndroidScanMode.lowLatency,
      );

      return true;
    } catch (e) {
      debugPrint('[BleHardwareService] Failed to start BLE scan: $e');
      _setStatus(BleScanStatus.error, e.toString());
      return false;
    }
  }
      return false;
    }
  }

  /// Stops active hardware scanning
  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (e) {
      debugPrint('[BleHardwareService] Error stopping scan: $e');
    } finally {
      await _scanResultsSub?.cancel();
      _scanResultsSub = null;
      _setStatus(BleScanStatus.idle);
    }
  }

  /// Release resources
  void dispose() {
    _scanResultsSub?.cancel();
    _adapterStateSub?.cancel();
    _statusController.close();
    _packetController.close();
  }
}
