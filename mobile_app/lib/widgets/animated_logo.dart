import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// AnimatedLogo displays a cyber shield with pulsing concentric radar waves
/// and a high-tech cyan/amber gradient, optimized for 60 FPS animation.
class AnimatedLogo extends StatefulWidget {
  final double size;
  final bool isScanning;

  const AnimatedLogo({
    super.key,
    this.size = 120.0,
    this.isScanning = true,
  });

  @override
  State<AnimatedLogo> createState() => _AnimatedLogoState();
}

class _AnimatedLogoState extends State<AnimatedLogo>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void didUpdateWidget(AnimatedLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isScanning && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isScanning && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          size: Size(widget.size, widget.size),
          painter: _SentinelLogoPainter(
            animationValue: _controller.value,
            isScanning: widget.isScanning,
          ),
        );
      },
    );
  }
}

class _SentinelLogoPainter extends CustomPainter {
  final double animationValue;
  final bool isScanning;

  _SentinelLogoPainter({
    required this.animationValue,
    required this.isScanning,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.width / 2;

    // 1. Concentric pulsing radar waves (cyan to amber gradient)
    for (int i = 0; i < 3; i++) {
      final waveProgress = (animationValue + (i * 0.33)) % 1.0;
      final waveRadius = (baseRadius * 0.4) + (waveProgress * baseRadius * 0.55);
      final waveOpacity = (1.0 - waveProgress) * 0.45;

      final wavePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..shader = SweepGradient(
          colors: const [
            AppColors.cyberCyan,
            AppColors.threatMedium,
            AppColors.cyberCyan,
          ],
          transform: GradientRotation(animationValue * 2 * math.pi),
        ).createShader(Rect.fromCircle(center: center, radius: waveRadius))
        ..color = AppColors.cyberCyan.withOpacity(waveOpacity.clamp(0.0, 1.0));

      canvas.drawCircle(center, waveRadius, wavePaint);
    }

    // 2. Cyber Shield Outline Path
    final shieldWidth = size.width * 0.62;
    final shieldHeight = size.height * 0.72;
    final top = center.dy - (shieldHeight / 2);
    final bottom = center.dy + (shieldHeight / 2);
    final left = center.dx - (shieldWidth / 2);
    final right = center.dx + (shieldWidth / 2);

    final shieldPath = Path()
      ..moveTo(center.dx, top) // Top center apex
      ..lineTo(right - 8, top + 4)
      ..quadraticBezierTo(right, top + 6, right, top + 16)
      ..lineTo(right, center.dy + 8)
      ..quadraticBezierTo(right, bottom - 18, center.dx, bottom)
      ..quadraticBezierTo(left, bottom - 18, left, center.dy + 8)
      ..lineTo(left, top + 16)
      ..quadraticBezierTo(left, top + 6, left + 8, top + 4)
      ..close();

    // Shield background fill (dark cyber glass)
    final shieldFillPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppColors.surfaceElevated.withOpacity(0.9),
          AppColors.surfaceDark.withOpacity(0.95),
        ],
      ).createShader(Rect.fromLTWH(left, top, shieldWidth, shieldHeight));

    canvas.drawPath(shieldPath, shieldFillPaint);

    // Shield glowing border with cyan / amber gradient
    final shieldBorderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AppColors.cyberCyan,
          AppColors.threatMedium,
          AppColors.cyberCyan,
        ],
        stops: [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTWH(left, top, shieldWidth, shieldHeight));

    canvas.drawPath(shieldPath, shieldBorderPaint);

    // 3. Central Sentinel Eye / Core Symbol
    final corePaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = const RadialGradient(
        colors: [
          AppColors.cyberCyan,
          AppColors.amoledBlack,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: 18));

    canvas.drawCircle(center, 12, corePaint);

    // Dynamic rotating cross-reticle
    final reticleAngle = animationValue * 2 * math.pi;
    final reticlePaint = Paint()
      ..color = AppColors.threatMedium
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final rayLen = 16.0;
    for (int r = 0; r < 4; r++) {
      final angle = reticleAngle + (r * (math.pi / 2));
      final p1 = Offset(
        center.dx + math.cos(angle) * 6,
        center.dy + math.sin(angle) * 6,
      );
      final p2 = Offset(
        center.dx + math.cos(angle) * rayLen,
        center.dy + math.sin(angle) * rayLen,
      );
      canvas.drawLine(p1, p2, reticlePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SentinelLogoPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.isScanning != isScanning;
  }
}
