import 'package:flutter/material.dart';

/// AppColors encapsulates the 2026 AMOLED Cyber & Material You 3.0 palette
/// tailored for high-contrast OLED displays (e.g. Google Pixel 9/10 Pro).
class AppColors {
  AppColors._();

  // Dark AMOLED Backgrounds
  static const Color amoledBlack = Color(0xFF0C0E14);
  static const Color surfaceDark = Color(0xFF141721);
  static const Color surfaceLight = Color(0xFF1C2030);
  static const Color surfaceElevated = Color(0xFF242A40);
  static const Color surfaceGlass = Color(0x331C2030);

  // 2026 Neon Accents
  static const Color cyberCyan = Color(0xFF00E5FF);
  static const Color neonGreen = Color(0xFF39FF14);
  static const Color threatCritical = Color(0xFFFF3D71);
  static const Color threatHigh = Color(0xFFFF8A00);
  static const Color threatMedium = Color(0xFFFFB300);
  static const Color threatLow = Color(0xFF00B0FF);
  static const Color threatSafe = Color(0xFF00E676);

  // Radar Palette
  static const Color radarGrid = Color(0x2600E5FF);
  static const Color radarGridHighlight = Color(0x4D00E5FF);
  static const Color radarSweepBeam = Color(0x6600E5FF);
  static const Color radarPhosphor = Color(0x1A00E5FF);
  static const Color radarCenter = Color(0xFF00E5FF);

  // Text & Content Hierarchy
  static const Color textPrimary = Color(0xFFF1F5F9);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);
  static const Color textInverse = Color(0xFF0C0E14);

  // Border & Glow Accents
  static const Color borderSubtle = Color(0xFF262D42);
  static const Color borderHighlight = Color(0x6600E5FF);
  static const Color glowCyan = Color(0x4000E5FF);
  static const Color glowCritical = Color(0x50FF3D71);
  static const Color glowSafe = Color(0x4000E676);

  // Geiger Counter Gradients
  static const LinearGradient geigerHeatGradient = LinearGradient(
    colors: [
      Color(0xFF00E676),
      Color(0xFFFFB300),
      Color(0xFFFF8A00),
      Color(0xFFFF3D71),
    ],
    stops: [0.0, 0.45, 0.75, 1.0],
  );

  static const LinearGradient cyberCardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF181C28),
      Color(0xFF12151F),
    ],
  );
}
