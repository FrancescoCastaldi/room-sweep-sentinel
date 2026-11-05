import 'package:flutter/material.dart';
import '../models/device_model.dart';
import '../theme/app_colors.dart';

/// DeviceCard displays detailed counter-surveillance metadata for an RF transmitter,
/// including animated RSSI signal strength meter, vendor OUI badge,
/// threat level classification, and direct launch into Geiger tracking.
class DeviceCard extends StatelessWidget {
  final RFDevice device;
  final VoidCallback? onGeigerTrack;
  final VoidCallback? onTap;
  final bool isSelected;

  const DeviceCard({
    super.key,
    required this.device,
    this.onGeigerTrack,
    this.onTap,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final threatColor = device.threatLevel.color;
    final isCriticalOrHigh = device.threatLevel == ThreatLevel.CRITICAL ||
        device.threatLevel == ThreatLevel.HIGH;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isSelected
              ? AppColors.cyberCyan
              : (isCriticalOrHigh
                  ? threatColor.withOpacity(0.5)
                  : AppColors.borderSubtle),
          width: isSelected ? 2.0 : (isCriticalOrHigh ? 1.5 : 1.0),
        ),
        boxShadow: [
          if (isSelected || isCriticalOrHigh)
            BoxShadow(
              color: (isSelected ? AppColors.cyberCyan : threatColor)
                  .withOpacity(0.12),
              blurRadius: 16,
              spreadRadius: 2,
            ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Protocol, Name, Threat Badge
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildProtocolIcon(device.protocol),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  device.name,
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.3,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (device.isHidden) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.threatCritical.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'HIDDEN',
                                    style: TextStyle(
                                      color: AppColors.threatCritical,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            device.macAddress,
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 12,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildThreatBadge(device.threatLevel, device.threatScore),
                  ],
                ),

                const SizedBox(height: 14),

                // Vendor OUI & Frequency / Channel Row
                Row(
                  children: [
                    _buildVendorChip(device.vendor),
                    const SizedBox(width: 8),
                    if (device.channel != null)
                      _buildInfoChip('CH ${device.channel}'),
                    if (device.frequencyMhz != null) ...[
                      const SizedBox(width: 6),
                      _buildInfoChip('${device.frequencyMhz} MHz'),
                    ],
                  ],
                ),

                const SizedBox(height: 14),

                // Animated RSSI Meter & Distance Row
                _buildRssiAndDistanceMeter(device),

                // Threat Reasons (if any)
                if (device.threatReasons.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: threatColor.withOpacity(0.25),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: device.threatReasons.take(2).map((reason) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.arrow_right_rounded,
                                size: 16,
                                color: threatColor,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  reason,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 11.5,
                                    height: 1.25,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],

                const SizedBox(height: 14),

                // Bottom Action: Launch Geiger Proximity Tracker
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isCriticalOrHigh
                          ? AppColors.threatCritical.withOpacity(0.18)
                          : AppColors.cyberCyan.withOpacity(0.12),
                      foregroundColor: isCriticalOrHigh
                          ? AppColors.threatCritical
                          : AppColors.cyberCyan,
                      side: BorderSide(
                        color: isCriticalOrHigh
                            ? AppColors.threatCritical.withOpacity(0.6)
                            : AppColors.cyberCyan.withOpacity(0.5),
                        width: 1.2,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    onPressed: onGeigerTrack,
                    icon: Icon(
                      Icons.radar_rounded,
                      size: 18,
                      color: isCriticalOrHigh
                          ? AppColors.threatCritical
                          : AppColors.cyberCyan,
                    ),
                    label: Text(
                      'PINPOINT CON TRACKER GEIGER',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                        color: isCriticalOrHigh
                            ? AppColors.threatCritical
                            : AppColors.cyberCyan,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProtocolIcon(ProtocolType protocol) {
    final isWifi = protocol == ProtocolType.WIFI;
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: (isWifi ? AppColors.cyberCyan : AppColors.neonGreen)
            .withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: (isWifi ? AppColors.cyberCyan : AppColors.neonGreen)
              .withOpacity(0.4),
        ),
      ),
      child: Icon(
        isWifi ? Icons.wifi_tethering_rounded : Icons.bluetooth_searching_rounded,
        color: isWifi ? AppColors.cyberCyan : AppColors.neonGreen,
        size: 22,
      ),
    );
  }

  Widget _buildThreatBadge(ThreatLevel level, int score) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: level.color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: level.color.withOpacity(0.6), width: 1.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(level.icon, size: 14, color: level.color),
          const SizedBox(width: 5),
          Text(
            '${level.label} ($score%)',
            style: TextStyle(
              color: level.color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVendorChip(String vendor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.memory_rounded, size: 12, color: AppColors.textMuted),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Text(
              vendor,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 10.5,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildRssiAndDistanceMeter(RFDevice device) {
    final strength = device.signalStrengthFraction;
    final distLabel = device.distanceCategoryLabel;
    final meters = device.estimatedDistanceMeters;

    Color meterColor;
    if (device.rssi > -45) {
      meterColor = AppColors.threatCritical;
    } else if (device.rssi > -65) {
      meterColor = AppColors.threatMedium;
    } else {
      meterColor = AppColors.cyberCyan;
    }

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(Icons.podcasts_rounded, size: 14, color: meterColor),
                const SizedBox(width: 5),
                Text(
                  '${device.rssi} dBm',
                  style: TextStyle(
                    color: meterColor,
                    fontSize: 13,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Icon(Icons.social_distance_rounded, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  '~${meters.toStringAsFixed(1)} m · $distLabel',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: strength,
            minHeight: 6,
            backgroundColor: AppColors.surfaceElevated,
            valueColor: AlwaysStoppedAnimation<Color>(meterColor),
          ),
        ),
      ],
    );
  }
}
