import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/device_model.dart';
import '../theme/app_colors.dart';

/// GeigerTrackerSheet is an acoustic and tactile "hot/cold" proximity tracker
/// designed to pinpoint covert RF bugs, hidden spy cameras, and audio transmitters.
class GeigerTrackerSheet extends StatefulWidget {
  final RFDevice device;
  final VoidCallback? onClose;
  final ValueChanged<RFDevice>? onDeviceFlagged;

  const GeigerTrackerSheet({
    super.key,
    required this.device,
    this.onClose,
    this.onDeviceFlagged,
  });

  static Future<void> show(
    BuildContext context, {
    required RFDevice device,
    ValueChanged<RFDevice>? onDeviceFlagged,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => GeigerTrackerSheet(
        device: device,
        onClose: () => Navigator.of(ctx).pop(),
        onDeviceFlagged: onDeviceFlagged,
      ),
    );
  }

  @override
  State<GeigerTrackerSheet> createState() => _GeigerTrackerSheetState();
}

class _GeigerTrackerSheetState extends State<GeigerTrackerSheet>
    with SingleTickerProviderStateMixin {
  late RFDevice _currentDevice;
  bool _audioFeedbackEnabled = true;
  bool _hapticFeedbackEnabled = true;
  bool _torchModeActive = false;
  double _sensitivityMultiplier = 1.0;

  Timer? _tickTimer;
  Timer? _jitterTimer;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _currentDevice = widget.device;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _restartGeigerLoop();

    // Simulate subtle real-world RF RSSI jitter while tracking
    _jitterTimer = Timer.periodic(const Duration(milliseconds: 700), (t) {
      if (!mounted) return;
      final rand = math.Random();
      final jitter = (rand.nextInt(3) - 1);
      final newRssi = (_currentDevice.rssi + jitter).clamp(-90, -25);
      final newDist = RFDevice.calculateDistance(newRssi);

      setState(() {
        _currentDevice = _currentDevice.copyWith(
          rssi: newRssi,
          estimatedDistanceMeters: newDist,
          lastSeen: DateTime.now(),
        );
      });
      _restartGeigerLoop();
    });
  }

  void _restartGeigerLoop() {
    _tickTimer?.cancel();

    // Calculate click interval from signal strength:
    // RSSI -25 dBm (within 30cm) -> 90ms (rapid clicks)
    // RSSI -90 dBm (far) -> 1200ms (slow clicks)
    final clamped = _currentDevice.rssi.clamp(-90, -25);
    final ratio = ((clamped - (-90)) / (-25 - (-90))).clamp(0.0, 1.0);
    final intervalMs = ((1200 - (ratio * 1110)) / _sensitivityMultiplier)
        .round()
        .clamp(60, 1400);

    _tickTimer = Timer.periodic(Duration(milliseconds: intervalMs), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _triggerGeigerTick(ratio);
    });
  }

  void _triggerGeigerTick(double proximityRatio) {
    if (_hapticFeedbackEnabled) {
      if (proximityRatio > 0.75) {
        HapticFeedback.heavyImpact();
      } else if (proximityRatio > 0.45) {
        HapticFeedback.mediumImpact();
      } else {
        HapticFeedback.selectionClick();
      }
    }
    if (_audioFeedbackEnabled) {
      SystemSound.play(SystemSoundType.click);
    }
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _jitterTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  String _getProximityHeatLabel(double distance) {
    if (distance <= 0.5) {
      return 'CALDISSIMO · CONTATTO DIRETTO IMMINENTE';
    } else if (distance <= 1.2) {
      return 'MOLTO CALDO · SOTTO IL METRO';
    } else if (distance <= 2.5) {
      return 'TIEPIDO · IN QUESTO SETTORE';
    } else if (distance <= 4.0) {
      return 'FRESCO · RAGGIO MEDIO';
    } else {
      return 'GELIDO · OLTRE 4 METRI';
    }
  }

  Color _getProximityColor(double distance) {
    if (distance <= 0.8) {
      return AppColors.threatCritical;
    } else if (distance <= 1.8) {
      return AppColors.threatHigh;
    } else if (distance <= 3.5) {
      return AppColors.threatMedium;
    } else {
      return AppColors.cyberCyan;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dist = _currentDevice.estimatedDistanceMeters;
    final proximityColor = _getProximityColor(dist);
    final heatLabel = _getProximityHeatLabel(dist);
    final proximityRatio = _currentDevice.signalStrengthFraction;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag Handle
              Center(
                child: Container(
                  width: 48,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderSubtle,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Title Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: proximityColor.withOpacity(0.16),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: proximityColor.withOpacity(0.5),
                          ),
                        ),
                        child: Icon(Icons.podcasts_rounded,
                            size: 20, color: proximityColor),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'TRACKER GEIGER',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                          Text(
                            'LOCALIZZAZIONE ELETTROMAGNETICA',
                            style: TextStyle(
                              color: proximityColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: widget.onClose ?? () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: AppColors.textMuted),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // Target Device Banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.borderSubtle),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _currentDevice.name,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${_currentDevice.macAddress} · ${_currentDevice.vendor}',
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _currentDevice.threatLevel.color.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _currentDevice.threatLevel.label,
                        style: TextStyle(
                          color: _currentDevice.threatLevel.color,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Geiger Circular Gauge Widget
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 200,
                    height: 200,
                    child: CustomPaint(
                      painter: _GeigerGaugePainter(
                        proximityRatio: proximityRatio,
                        proximityColor: proximityColor,
                        pulseValue: _pulseController.value,
                      ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '~${dist.toStringAsFixed(1)} m',
                        style: TextStyle(
                          color: proximityColor,
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1.0,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_currentDevice.rssi} dBm',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Heat State Pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: proximityColor.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: proximityColor.withOpacity(0.6)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.whatshot_rounded, size: 16, color: proximityColor),
                    const SizedBox(width: 6),
                    Text(
                      heatLabel,
                      style: TextStyle(
                        color: proximityColor,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // Feedback Controls Bar (Audio, Haptic, Torch for Lens Glare)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildToggleChip(
                    icon: _audioFeedbackEnabled
                        ? Icons.volume_up_rounded
                        : Icons.volume_off_rounded,
                    label: 'Audio Click',
                    isActive: _audioFeedbackEnabled,
                    onTap: () {
                      setState(() {
                        _audioFeedbackEnabled = !_audioFeedbackEnabled;
                      });
                      _restartGeigerLoop();
                    },
                  ),
                  _buildToggleChip(
                    icon: Icons.vibration_rounded,
                    label: 'Vibrazione',
                    isActive: _hapticFeedbackEnabled,
                    onTap: () {
                      setState(() {
                        _hapticFeedbackEnabled = !_hapticFeedbackEnabled;
                      });
                    },
                  ),
                  _buildToggleChip(
                    icon: _torchModeActive
                        ? Icons.flash_on_rounded
                        : Icons.flash_off_rounded,
                    label: 'Torcia Lente',
                    isActive: _torchModeActive,
                    onTap: () {
                      setState(() {
                        _torchModeActive = !_torchModeActive;
                      });
                      HapticFeedback.lightImpact();
                    },
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        side: const BorderSide(color: AppColors.borderSubtle),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_rounded, size: 18),
                      label: const Text('CHIUDI TRACKER'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.threatCritical,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () {
                        widget.onDeviceFlagged?.call(_currentDevice);
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Dispositivo ${_currentDevice.macAddress} contrassegnato per neutralizzazione forense.',
                            ),
                            backgroundColor: AppColors.surfaceElevated,
                          ),
                        );
                      },
                      icon: const Icon(Icons.security_rounded, size: 18),
                      label: const Text('ISOLA MINACCIA'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToggleChip({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.cyberCyan.withOpacity(0.18)
              : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive ? AppColors.cyberCyan : AppColors.borderSubtle,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isActive ? AppColors.cyberCyan : AppColors.textMuted,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isActive ? AppColors.cyberCyan : AppColors.textSecondary,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GeigerGaugePainter extends CustomPainter {
  final double proximityRatio;
  final Color proximityColor;
  final double pulseValue;

  _GeigerGaugePainter({
    required this.proximityRatio,
    required this.proximityColor,
    required this.pulseValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 14;

    const startAngle = 0.75 * math.pi;
    const sweepTotalAngle = 1.5 * math.pi;

    // Background track arc
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round
      ..color = AppColors.surfaceElevated;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepTotalAngle,
      false,
      trackPaint,
    );

    // Dynamic active proximity arc
    final activeSweep = sweepTotalAngle * proximityRatio.clamp(0.05, 1.0);
    final activePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round
      ..color = proximityColor;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      activeSweep,
      false,
      activePaint,
    );

    // Glowing outer ripple pulse for high proximity
    if (proximityRatio > 0.5) {
      final pulseRadius = radius + (pulseValue * 8);
      final pulsePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..color = proximityColor.withOpacity((1.0 - pulseValue) * 0.6);
      canvas.drawCircle(center, pulseRadius, pulsePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _GeigerGaugePainter oldDelegate) {
    return oldDelegate.proximityRatio != proximityRatio ||
        oldDelegate.proximityColor != proximityColor ||
        oldDelegate.pulseValue != pulseValue;
  }
}
