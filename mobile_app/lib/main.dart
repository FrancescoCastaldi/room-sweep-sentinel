import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'services/scanner_service.dart';
import 'services/audit_logger_service.dart';
import 'services/update_checker_service.dart';
import 'widgets/update_dialog.dart';
import 'theme/app_theme.dart';
import 'theme/app_colors.dart';
import 'screens/radar_sweep_screen.dart';
import 'screens/device_list_screen.dart';
import 'screens/audit_report_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Configure high-contrast AMOLED system overlay
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.amoledBlack,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarDividerColor: Colors.transparent,
    ),
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ScannerService()),
        ChangeNotifierProvider(create: (_) => AuditLoggerService()),
        ChangeNotifierProvider(create: (_) => UpdateCheckerService()),
      ],
      child: const RoomSweepSentinelApp(),
    ),
  );
}

class RoomSweepSentinelApp extends StatelessWidget {
  const RoomSweepSentinelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Room Sweep Sentinel',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const MainNavigationShell(),
    );
  }
}

class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({super.key});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    // Non-intrusive background check for software updates and auto-start RF sweep on launch
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdatesOnStartup();
      final scanner = context.read<ScannerService>();
      if (!scanner.isScanning) {
        scanner.startScan();
      }
    });
  }

  void _checkForUpdatesOnStartup() {
    final updater = context.read<UpdateCheckerService>();
    updater.checkForUpdates(silent: true).then((release) {
      if (release != null && release.isNewerThanCurrent && mounted) {
        UpdateDialog.show(context, release);
      }
    });
  }

  final List<Widget> _screens = const [
    RadarSweepScreen(),
    DeviceListScreen(),
    AuditReportScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final scanner = context.watch<ScannerService>();
    final threatCount = scanner.allThreats.length;

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.amoledBlack,
          border: Border(
            top: BorderSide(color: AppColors.borderSubtle, width: 0.8),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) {
            if (_currentIndex != index) {
              HapticFeedback.selectionClick();
              setState(() {
                _currentIndex = index;
              });
            }
          },
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.radar_outlined),
              selectedIcon: Icon(Icons.radar_rounded),
              label: 'Radar Sweep',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: threatCount > 0,
                label: Text(
                  '$threatCount',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 10),
                ),
                backgroundColor: AppColors.threatCritical,
                child: const Icon(Icons.wifi_find_outlined),
              ),
              selectedIcon: Badge(
                isLabelVisible: threatCount > 0,
                label: Text(
                  '$threatCount',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 10),
                ),
                backgroundColor: AppColors.threatCritical,
                child: const Icon(Icons.wifi_find_rounded),
              ),
              label: 'Dispositivi RF',
            ),
            const NavigationDestination(
              icon: Icon(Icons.verified_outlined),
              selectedIcon: Icon(Icons.verified_rounded),
              label: 'Audit NIS2',
            ),
          ],
        ),
      ),
    );
  }
}
