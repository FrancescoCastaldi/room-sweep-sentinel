import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/device_model.dart';
import '../services/scanner_service.dart';
import '../services/audit_logger_service.dart';
import '../theme/app_colors.dart';
import '../widgets/radar_display.dart';
import '../widgets/geiger_tracker_sheet.dart';
import '../widgets/animated_logo.dart';

class RadarSweepScreen extends StatelessWidget {
  const RadarSweepScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scanner = context.watch<ScannerService>();
    final auditLogger = context.read<AuditLoggerService>();

    final criticalThreats = scanner.criticalThreats;
    final allThreats = scanner.allThreats;
    final hasThreats = allThreats.isNotEmpty;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Top App Bar / Status Banner
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      AnimatedLogo(
                        size: 38,
                        isScanning: scanner.isScanning,
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ROOM SWEEP SENTINEL',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                          Row(
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: scanner.isScanning
                                      ? AppColors.neonGreen
                                      : AppColors.textMuted,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                scanner.isScanning
                                    ? 'SWEEP 360° IN ESECUZIONE'
                                    : 'STANDBY · PRONTO',
                                style: TextStyle(
                                  color: scanner.isScanning
                                      ? AppColors.neonGreen
                                      : AppColors.textMuted,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),

                  // NIS2 Certification Mini-Pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.borderSubtle),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.verified_rounded, size: 13, color: AppColors.cyberCyan),
                        SizedBox(width: 5),
                        Text(
                          'NIS2 AUDIT',
                          style: TextStyle(
                            color: AppColors.cyberCyan,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Metrics Summary Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  _buildStatTile(
                    label: 'DISPOSITIVI',
                    value: '${scanner.devices.length}',
                    color: AppColors.cyberCyan,
                    icon: Icons.wifi_find_rounded,
                  ),
                  const SizedBox(width: 10),
                  _buildStatTile(
                    label: 'MINACCE RF',
                    value: '${allThreats.length}',
                    color: hasThreats ? AppColors.threatCritical : AppColors.threatSafe,
                    icon: hasThreats ? Icons.warning_rounded : Icons.check_circle_rounded,
                  ),
                  const SizedBox(width: 10),
                  _buildStatTile(
                    label: 'RAGGIO',
                    value: '10 m',
                    color: AppColors.textSecondary,
                    icon: Icons.track_changes_rounded,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Central Interactive Sweeping Radar
            Expanded(
              child: Center(
                child: RadarDisplay(
                  devices: scanner.devices,
                  sweepAngle: scanner.radarAngle,
                  maxRangeMeters: 10.0,
                  size: 320.0,
                  onDeviceTapped: (device) {
                    HapticFeedback.lightImpact();
                    auditLogger.logEvent('RADAR_BLIP_SELECTED', {
                      'device_id': device.id,
                      'mac': device.macAddress,
                      'threat': device.threatLevel.name,
                    });
                    GeigerTrackerSheet.show(
                      context,
                      device: device,
                      onDeviceFlagged: (flagged) {
                        auditLogger.logEvent('DEVICE_FLAGGED_FOR_NEUTRALIZATION', {
                          'mac': flagged.macAddress,
                          'rssi': flagged.rssi,
                        });
                      },
                    );
                  },
                ),
              ),
            ),

            // Detected Threats Quick Reel
            if (criticalThreats.isNotEmpty || allThreats.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'MINACCE IN PROSSIMITÀ IMMEDIATA',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Text(
                      'Tocca per il Tracker Geiger',
                      style: TextStyle(
                        color: AppColors.cyberCyan.withOpacity(0.8),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 86,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: allThreats.length,
                  itemBuilder: (context, index) {
                    final threat = allThreats[index];
                    return _buildThreatQuickCard(context, threat, auditLogger);
                  },
                ),
              ),
            ],

            const SizedBox(height: 12),

            // Main Sweep Toggle Action Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: scanner.isScanning
                        ? AppColors.surfaceLight
                        : AppColors.cyberCyan,
                    foregroundColor: scanner.isScanning
                        ? AppColors.threatCritical
                        : AppColors.textInverse,
                    side: BorderSide(
                      color: scanner.isScanning
                          ? AppColors.threatCritical.withOpacity(0.6)
                          : AppColors.cyberCyan,
                      width: 1.5,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    if (scanner.isScanning) {
                      scanner.stopScan();
                      auditLogger.logEvent('SWEEP_STOPPED_MANUALLY', {
                        'devices_count': scanner.devices.length,
                      });
                    } else {
                      scanner.startScan();
                      auditLogger.logEvent('SWEEP_STARTED', {
                        'scan_profile': 'Full 360 Spectrum 2.4/5.8GHz & BLE',
                      });
                    }
                  },
                  icon: Icon(
                    scanner.isScanning ? Icons.stop_rounded : Icons.radar_rounded,
                    size: 22,
                  ),
                  label: Text(
                    scanner.isScanning
                        ? 'ARRESTA BONIFICA ATTIVA'
                        : 'AVVIA SWEEP RADAR 360°',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatTile({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.borderSubtle),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThreatQuickCard(
    BuildContext context,
    RFDevice threat,
    AuditLoggerService auditLogger,
  ) {
    final color = threat.threatLevel.color;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        GeigerTrackerSheet.show(
          context,
          device: threat,
          onDeviceFlagged: (flagged) {
            auditLogger.logEvent('DEVICE_FLAGGED_FOR_NEUTRALIZATION', {
              'mac': flagged.macAddress,
            });
          },
        );
      },
      child: Container(
        width: 220,
        margin: const EdgeInsets.only(right: 10, top: 4, bottom: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.5), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.12),
              blurRadius: 8,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withOpacity(0.15),
              ),
              child: Icon(threat.threatLevel.icon, size: 18, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    threat.name,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '~${threat.estimatedDistanceMeters.toStringAsFixed(1)} m · ${threat.rssi} dBm',
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
