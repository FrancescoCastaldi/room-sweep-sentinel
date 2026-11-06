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
  /// - Android <= 11: ACCESS_FINE_LOCATION / ACCESS_COARSE_LOCATION
  Future<bool> checkAndRequestPermissions() async {
    _setStatus(BleScanStatus.checkingPermissions);

    try {
      if (Platform.isAndroid) {
        final permissions = [
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
          Permission.locationWhenInUse,
        ];

        final statuses = await permissions.request();

        final scanStatus = statuses[Permission.bluetoothScan];
        final connectStatus = statuses[Permission.bluetoothConnect];
        final locationStatus = statuses[Permission.locationWhenInUse];

        final scanGranted = scanStatus?.isGranted ?? false;
        final connectGranted = connectStatus?.isGranted ?? false;
        final locationGranted = locationStatus?.isGranted ?? false;

        // On Android 12+, scan & connect are essential. On legacy Android, location is mandatory.
        final isPermitted = (scanGranted && connectGranted) || locationGranted;

        if (!isPermitted) {
          _setStatus(
            BleScanStatus.permissionDenied,
            'Permessi Bluetooth o Posizione negati dall\'utente.',
          );
          return false;
        }
      }
      return true;
    } catch (e) {
      debugPrint('[BleHardwareService] Permission request failed: $e');
      _setStatus(BleScanStatus.permissionDenied, e.toString());
      return false;
    }
  }

  /// Checks if device Bluetooth hardware is turned on, attempting prompt if disabled
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

      BluetoothAdapterState state = await FlutterBluePlus.adapterState.first;
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
            'Bluetooth disattivato. Attiva il Bluetooth per avviare la bonifica RF.',
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

      // Start continuous scanning with low latency mode
      await FlutterBluePlus.startScan(
        continuousUpdates: true,
        androidScanMode: AndroidScanMode.lowLatency,
      );

      return true;
    } catch (e) {
      debugPrint('[BleHardwareService] Failed to start BLE scan: $e');
      _setStatus(BleScanStatus.error, e.toString());
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
