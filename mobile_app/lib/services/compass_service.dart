import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// CompassService connects to the native Android Rotation Vector HAL
/// and streams smoothed magnetic azimuth heading (0.0° - 360.0°).
class CompassService extends ChangeNotifier {
  static const EventChannel _compassChannel =
      EventChannel('com.francescocastaldi.roomsentinel/compass');

  StreamSubscription<dynamic>? _subscription;
  double _heading = 0.0;
  bool _isAvailable = false;

  double get heading => _heading;
  bool get isAvailable => _isAvailable;

  CompassService() {
    _startListening();
  }

  void _startListening() {
    try {
      _subscription = _compassChannel.receiveBroadcastStream().listen(
        (dynamic event) {
          if (event is num) {
            final rawHeading = (event.toDouble() + 360.0) % 360.0;
            _updateHeading(rawHeading);
          }
        },
        onError: (dynamic err) {
          debugPrint('[CompassService] Compass stream error: $err');
          _isAvailable = false;
          notifyListeners();
        },
      );
    } catch (e) {
      debugPrint('[CompassService] Failed to bind compass channel: $e');
      _isAvailable = false;
    }
  }

  /// Smooths heading updates across 0° / 360° modular boundary
  void _updateHeading(double targetHeading) {
    _isAvailable = true;
    // Calculate shortest angular distance to prevent wild spins across 359° <-> 0°
    final delta = ((targetHeading - _heading + 540.0) % 360.0) - 180.0;
    // Low-pass filter for smooth radar rotation (~15-20% step per event)
    _heading = (_heading + (delta * 0.35) + 360.0) % 360.0;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
