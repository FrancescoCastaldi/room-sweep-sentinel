import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/device_model.dart';
import '../theme/app_colors.dart';

/// RadarDisplay is an interactive, animated 360° sweeping counter-surveillance radar
/// with real-time Heading-Up orientation driven by the device's hardware compass.
///
/// Top of the radar always represents "Ahead" (where the phone antenna is pointed).
/// Cardinal points (N, E, S, W) and transmitter blips rotate dynamically as the operator turns.
class RadarDisplay extends StatelessWidget {
  final List<RFDevice> devices;
  final double sweepAngle; // in degrees (0 - 360)
  final double phoneHeading; // in degrees (0 - 360) from hardware compass
  final double maxRangeMeters;
  final ValueChanged<RFDevice>? onDeviceTapped;
  final String? highlightedDeviceId;
  final double size;

  const RadarDisplay({
    super.key,
    required this.devices,
    required this.sweepAngle,
    this.phoneHeading = 0.0,
    this.maxRangeMeters = 10.0,
    this.onDeviceTapped,
    this.highlightedDeviceId,
    this.size = 320.0,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTapDown: (details) => _handleTap(details, context),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.amoledBlack,
            boxShadow: [
              BoxShadow(
                color: AppColors.cyberCyan.withOpacity(0.08),
                blurRadius: 32,
                spreadRadius: 8,
              ),
            ],
          ),
          child: CustomPaint(
            size: Size(size, size),
            painter: _RadarDisplayPainter(
              devices: devices,
              sweepAngle: sweepAngle,
              phoneHeading: phoneHeading,
              maxRangeMeters: maxRangeMeters,
              highlightedDeviceId: highlightedDeviceId,
            ),
          ),
        ),
      ),
    );
  }

  void _handleTap(TapDownDetails details, BuildContext context) {
    if (onDeviceTapped == null || devices.isEmpty) return;

    final center = Offset(size / 2, size / 2);
    final radarRadius = (size / 2) - 16;
    final touchPos = details.localPosition;

    for (final dev in devices) {
      final pos = _deviceToOffset(dev, center, radarRadius);
      final distToTouch = (touchPos - pos).distance;
      if (distToTouch <= 26.0) {
        onDeviceTapped!(dev);
        return;
      }
    }
  }

  Offset _deviceToOffset(RFDevice dev, Offset center, double radarRadius) {
    final distRatio = (dev.estimatedDistanceMeters / maxRangeMeters).clamp(0.08, 1.0);
    final r = distRatio * radarRadius;
    // Heading-Up transformation: relative bearing relative to where the phone is pointing
    final relativeAngle = dev.relativeBearing(phoneHeading);
    final angleRad = (relativeAngle - 90.0) * (math.pi / 180.0);
    return Offset(
      center.dx + (r * math.cos(angleRad)),
      center.dy + (r * math.sin(angleRad)),
    );
  }
}

class _RadarDisplayPainter extends CustomPainter {
  final List<RFDevice> devices;
  final double sweepAngle;
  final double phoneHeading;
  final double maxRangeMeters;
  final String? highlightedDeviceId;

  _RadarDisplayPainter({
    required this.devices,
    required this.sweepAngle,
    required this.phoneHeading,
    required this.maxRangeMeters,
    this.highlightedDeviceId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radarRadius = (size.width / 2) - 16;

    // 1. Background dark gradient
    final bgPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          AppColors.surfaceDark.withOpacity(0.9),
          AppColors.amoledBlack,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radarRadius));
    canvas.drawCircle(center, radarRadius, bgPaint);

    // 2. Concentric distance rings: 1m, 3m, 5m, 10m
    final ringDistances = [1.0, 3.0, 5.0, 10.0];
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = AppColors.radarGrid;

    final highlightRingPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = AppColors.radarGridHighlight;

    for (final dist in ringDistances) {
      final r = (dist / maxRangeMeters) * radarRadius;
      final isOuter = dist == 10.0;
      canvas.drawCircle(center, r, isOuter ? highlightRingPaint : ringPaint);

      // Draw Range Distance Labels on the vertical axis
      _drawText(
        canvas,
        '${dist.toInt()}m',
        Offset(center.dx + 4, center.dy - r + 3),
        AppColors.textMuted,
        9.0,
      );
    }

    // 3. Grid Axes & Radial lines
    final axisPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = AppColors.radarGrid;

    // Fixed crosshairs representing relative orientation:
    // Vertical = Front/Back axis, Horizontal = Left/Right axis
    canvas.drawLine(
      Offset(center.dx - radarRadius, center.dy),
      Offset(center.dx + radarRadius, center.dy),
      axisPaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radarRadius),
      Offset(center.dx, center.dy + radarRadius),
      axisPaint,
    );

    // Diagonal reference lines (45°, 135°)
    final diagOffset = radarRadius * math.cos(math.pi / 4);
    final diagPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = AppColors.radarGrid.withOpacity(0.4);

    canvas.drawLine(
      Offset(center.dx - diagOffset, center.dy - diagOffset),
      Offset(center.dx + diagOffset, center.dy + diagOffset),
      diagPaint,
    );
    canvas.drawLine(
      Offset(center.dx - diagOffset, center.dy + diagOffset),
      Offset(center.dx + diagOffset, center.dy - diagOffset),
      diagPaint,
    );

    // 4. Dynamic Cardinal Labels (Rotating with Compass Heading)
    _drawRotatingCardinal(canvas, center, radarRadius - 10, 'N', 0.0, isNorth: true);
    _drawRotatingCardinal(canvas, center, radarRadius - 10, 'E', 90.0);
    _drawRotatingCardinal(canvas, center, radarRadius - 10, 'S', 180.0);
    _drawRotatingCardinal(canvas, center, radarRadius - 10, 'W', 270.0);

    // Forward Heading Reticle at Top (0° / Ahead)
    final forwardIndicatorPaint = Paint()
      ..color = AppColors.neonGreen
      ..style = PaintingStyle.fill;
    final topPoint = Offset(center.dx, center.dy - radarRadius + 2);
    final arrowPath = Path()
      ..moveTo(topPoint.dx, topPoint.dy)
      ..lineTo(topPoint.dx - 4, topPoint.dy + 8)
      ..lineTo(topPoint.dx + 4, topPoint.dy + 8)
      ..close();
    canvas.drawPath(arrowPath, forwardIndicatorPaint);

    // 5. Sweeping phosphor beam (360° rotating cone)
    final sweepAngleRad = (sweepAngle - 90.0) * (math.pi / 180.0);
    final trailAngleRad = sweepAngleRad - (math.pi / 3.0); // 60 degree trailing fade

    final sweepPath = Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(
        Rect.fromCircle(center: center, radius: radarRadius),
        trailAngleRad,
        math.pi / 3.0,
        false,
      )
      ..close();

    final sweepShader = SweepGradient(
      center: Alignment.center,
      startAngle: trailAngleRad,
      endAngle: sweepAngleRad,
      colors: [
        Colors.transparent,
        AppColors.cyberCyan.withOpacity(0.08),
        AppColors.cyberCyan.withOpacity(0.35),
      ],
      stops: const [0.0, 0.6, 1.0],
    ).createShader(Rect.fromCircle(center: center, radius: radarRadius));

    canvas.drawPath(sweepPath, Paint()..shader = sweepShader);

    // Leading active laser line
    final leadPoint = Offset(
      center.dx + (radarRadius * math.cos(sweepAngleRad)),
      center.dy + (radarRadius * math.sin(sweepAngleRad)),
    );
    final leadPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..shader = LinearGradient(
        colors: [
          AppColors.cyberCyan.withOpacity(0.2),
          AppColors.cyberCyan,
        ],
      ).createShader(Rect.fromPoints(center, leadPoint));
    canvas.drawLine(center, leadPoint, leadPaint);

    // 6. Draw Device Blips with Heading-Up Relative Positioning
    for (final dev in devices) {
      final distRatio = (dev.estimatedDistanceMeters / maxRangeMeters).clamp(0.08, 1.0);
      final r = distRatio * radarRadius;

      // Heading-Up transform: blip angle is relative to phone heading
      final relativeAngle = dev.relativeBearing(phoneHeading);
      final angleRad = (relativeAngle - 90.0) * (math.pi / 180.0);

      final blipPos = Offset(
        center.dx + (r * math.cos(angleRad)),
        center.dy + (r * math.sin(angleRad)),
      );

      // Check beam proximity for dynamic phosphorescent flash
      final angleDiffDeg = (relativeAngle - sweepAngle).abs() % 360;
      final minAngleDiff = math.min(angleDiffDeg, 360 - angleDiffDeg);
      final isBeamPassing = minAngleDiff < 32.0;
      final isHighlighted = dev.id == highlightedDeviceId;

      final blipColor = dev.threatLevel.color;

      // Glow halo
      final haloRadius = isHighlighted ? 18.0 : (isBeamPassing ? 14.0 : 8.0);
      final haloOpacity = isHighlighted ? 0.6 : (isBeamPassing ? 0.45 : 0.2);

      canvas.drawCircle(
        blipPos,
        haloRadius,
        Paint()
          ..style = PaintingStyle.fill
          ..color = blipColor.withOpacity(haloOpacity),
      );

      // Blip center dot
      final dotRadius = isHighlighted ? 6.5 : (isBeamPassing ? 5.5 : 4.0);
      canvas.drawCircle(
        blipPos,
        dotRadius,
        Paint()
          ..style = PaintingStyle.fill
          ..color = isBeamPassing ? Colors.white : blipColor,
      );

      // Threat severity ripple for CRITICAL or HIGH threats
      if (dev.threatLevel == ThreatLevel.CRITICAL || dev.threatLevel == ThreatLevel.HIGH) {
        canvas.drawCircle(
          blipPos,
          dotRadius + 4,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = blipColor.withOpacity(0.8),
        );
      }

      // Distance tag + short name
      final distLabel = '${dev.estimatedDistanceMeters.toStringAsFixed(1)}m';
      final shortName = dev.name.length > 10 ? '${dev.name.substring(0, 9)}..' : dev.name;
      _drawText(
        canvas,
        '$shortName ($distLabel)',
        Offset(blipPos.dx + 8, blipPos.dy - 6),
        isHighlighted ? AppColors.cyberCyan : AppColors.textPrimary,
        8.5,
        isBold: isHighlighted,
      );
    }

    // 7. Center Hub / Sentinel Core
    canvas.drawCircle(
      center,
      6.0,
      Paint()
        ..style = PaintingStyle.fill
        ..color = AppColors.cyberCyan,
    );
    canvas.drawCircle(
      center,
      10.0,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = AppColors.cyberCyan.withOpacity(0.5),
    );
  }

  void _drawRotatingCardinal(
    Canvas canvas,
    Offset center,
    double radius,
    String letter,
    double geographicAzimuth, {
    bool isNorth = false,
  }) {
    // Relative angle on radar = geographicAzimuth - phoneHeading
    final relAngle = (geographicAzimuth - phoneHeading + 360.0) % 360.0;
    final rad = (relAngle - 90.0) * (math.pi / 180.0);
    final pos = Offset(
      center.dx + (radius * math.cos(rad)) - 4,
      center.dy + (radius * math.sin(rad)) - 5,
    );
    _drawText(
      canvas,
      letter,
      pos,
      isNorth ? AppColors.neonGreen : AppColors.textMuted,
      isNorth ? 11.5 : 10.0,
      isBold: isNorth,
    );
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset position,
    Color color,
    double fontSize, {
    bool isBold = false,
  }) {
    final textSpan = TextSpan(
      text: text,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
        fontFamily: 'monospace',
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, position);
  }

  @override
  bool shouldRepaint(covariant _RadarDisplayPainter oldDelegate) {
    return oldDelegate.sweepAngle != sweepAngle ||
        oldDelegate.phoneHeading != phoneHeading ||
        oldDelegate.devices != devices ||
        oldDelegate.highlightedDeviceId != highlightedDeviceId;
  }
}
