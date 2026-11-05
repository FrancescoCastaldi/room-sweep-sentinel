import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/device_model.dart';
import '../services/scanner_service.dart';
import '../services/audit_logger_service.dart';
import '../theme/app_colors.dart';
import '../widgets/device_card.dart';
import '../widgets/geiger_tracker_sheet.dart';

enum DeviceFilter {
  all,
  threatsOnly,
  wifiOnly,
  bleOnly,
}

enum DeviceSort {
  byThreatScore,
  byProximity,
  byName,
}

class DeviceListScreen extends StatefulWidget {
  const DeviceListScreen({super.key});

  @override
  State<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends State<DeviceListScreen> {
  String _searchQuery = '';
  DeviceFilter _currentFilter = DeviceFilter.all;
  DeviceSort _currentSort = DeviceSort.byThreatScore;
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<RFDevice> _filterAndSortDevices(List<RFDevice> rawDevices) {
    var list = rawDevices.where((device) {
      // 1. Text Search matching name, MAC, or vendor
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchesName = device.name.toLowerCase().contains(q);
        final matchesMac = device.macAddress.toLowerCase().contains(q);
        final matchesVendor = device.vendor.toLowerCase().contains(q);
        if (!matchesName && !matchesMac && !matchesVendor) {
          return false;
        }
      }

      // 2. Category Filter
      switch (_currentFilter) {
        case DeviceFilter.threatsOnly:
          return device.threatLevel != ThreatLevel.SAFE;
        case DeviceFilter.wifiOnly:
          return device.protocol == ProtocolType.WIFI;
        case DeviceFilter.bleOnly:
          return device.protocol == ProtocolType.BLE;
        case DeviceFilter.all:
          return true;
      }
    }).toList();

    // 3. Sorting
    list.sort((a, b) {
      switch (_currentSort) {
        case DeviceSort.byThreatScore:
          return b.threatScore.compareTo(a.threatScore);
        case DeviceSort.byProximity:
          // Strongest signal / closest first
          return b.rssi.compareTo(a.rssi);
        case DeviceSort.byName:
          return a.name.compareTo(b.name);
      }
    });

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final scanner = context.watch<ScannerService>();
    final auditLogger = context.read<AuditLoggerService>();
    final filtered = _filterAndSortDevices(scanner.devices);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Screen Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'DISPOSITIVI RILEVATI',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${filtered.length} trasmettitori RF catalogati nello spettro',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),

                  // Rescan / Refresh Button
                  IconButton.filledTonal(
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.surfaceLight,
                      foregroundColor: AppColors.cyberCyan,
                    ),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      scanner.startScan();
                    },
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                  ),
                ],
              ),
            ),

            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceDark,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.borderSubtle),
                ),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                  cursorColor: AppColors.cyberCyan,
                  decoration: InputDecoration(
                    hintText: 'Cerca per nome, MAC address o vendor...',
                    hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                    prefixIcon: const Icon(Icons.search_rounded, color: AppColors.cyberCyan, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18, color: AppColors.textMuted),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val),
                ),
              ),
            ),

            const SizedBox(height: 10),

            // Filter Chips Bar
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _buildFilterChip('Tutti', DeviceFilter.all, scanner.devices.length),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    'Solo Minacce',
                    DeviceFilter.threatsOnly,
                    scanner.allThreats.length,
                    activeColor: AppColors.threatCritical,
                  ),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    'Wi-Fi',
                    DeviceFilter.wifiOnly,
                    scanner.devices.where((d) => d.protocol == ProtocolType.WIFI).length,
                  ),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    'BLE',
                    DeviceFilter.bleOnly,
                    scanner.devices.where((d) => d.protocol == ProtocolType.BLE).length,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // Devices List or Empty State
            Expanded(
              child: filtered.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final dev = filtered[index];
                        return DeviceCard(
                          device: dev,
                          onGeigerTrack: () {
                            HapticFeedback.selectionClick();
                            auditLogger.logEvent('GEIGER_TRACKER_ENGAGED_FROM_LIST', {
                              'mac': dev.macAddress,
                              'rssi': dev.rssi,
                            });
                            GeigerTrackerSheet.show(
                              context,
                              device: dev,
                              onDeviceFlagged: (flagged) {
                                auditLogger.logEvent('DEVICE_FLAGGED', {
                                  'mac': flagged.macAddress,
                                });
                              },
                            );
                          },
                          onTap: () {
                            HapticFeedback.lightImpact();
                            GeigerTrackerSheet.show(
                              context,
                              device: dev,
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(
    String label,
    DeviceFilter filter,
    int count, {
    Color? activeColor,
  }) {
    final isSelected = _currentFilter == filter;
    final color = activeColor ?? AppColors.cyberCyan;

    return ChoiceChip(
      label: Text('$label ($count)'),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          HapticFeedback.selectionClick();
          setState(() => _currentFilter = filter);
        }
      },
      selectedColor: color.withOpacity(0.2),
      backgroundColor: AppColors.surfaceDark,
      side: BorderSide(
        color: isSelected ? color : AppColors.borderSubtle,
        width: isSelected ? 1.4 : 1.0,
      ),
      labelStyle: TextStyle(
        color: isSelected ? color : AppColors.textSecondary,
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.search_off_rounded,
              size: 40,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Nessun trasmettitore trovato',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Prova a modificare i filtri o la query di ricerca.',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
