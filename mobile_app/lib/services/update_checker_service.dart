import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// Release metadata retrieved from GitHub Releases API
class AppReleaseInfo {
  final String tagName;
  final String name;
  final String releaseNotes;
  final DateTime publishedAt;
  final String apkDownloadUrl;
  final int apkSizeBytes;
  final bool isNewerThanCurrent;

  const AppReleaseInfo({
    required this.tagName,
    required this.name,
    required this.releaseNotes,
    required this.publishedAt,
    required this.apkDownloadUrl,
    required this.apkSizeBytes,
    required this.isNewerThanCurrent,
  });

  String get formattedSize {
    if (apkSizeBytes <= 0) return 'Dimensione sconosciuta';
    final mb = apkSizeBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }
}

/// UpdateCheckerService queries GitHub Releases, detects new builds,
/// downloads APKs with real-time stream progress, and triggers native Android package installation.
class UpdateCheckerService extends ChangeNotifier {
  static const String currentAppVersion = '1.2.1';
  static const String repoOwner = 'FrancescoCastaldi';
  static const String repoName = 'room-sweep-sentinel';

  static const MethodChannel _installerChannel =
      MethodChannel('com.francescocastaldi.roomsentinel/installer');

  bool _isChecking = false;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  int _downloadedBytes = 0;
  int _totalBytes = 0;
  String? _errorMessage;
  AppReleaseInfo? _latestRelease;

  bool get isChecking => _isChecking;
  bool get isDownloading => _isDownloading;
  double get downloadProgress => _downloadProgress;
  int get downloadedBytes => _downloadedBytes;
  int get totalBytes => _totalBytes;
  String? get errorMessage => _errorMessage;
  AppReleaseInfo? get latestRelease => _latestRelease;
  bool get hasUpdate => _latestRelease?.isNewerThanCurrent ?? false;

  /// Semantic version comparator
  /// Returns true if [remoteVersionTag] is strictly newer than [currentVersion]
  static bool isVersionNewer(String currentVersion, String remoteVersionTag) {
    try {
      final cleanCurrent = currentVersion.replaceAll(RegExp(r'^[vV]'), '').split('+').first;
      final cleanRemote = remoteVersionTag.replaceAll(RegExp(r'^[vV]'), '').split('+').first;

      final currentParts = cleanCurrent.split('.').map((p) => int.tryParse(p) ?? 0).toList();
      final remoteParts = cleanRemote.split('.').map((p) => int.tryParse(p) ?? 0).toList();

      while (currentParts.length < 3) currentParts.add(0);
      while (remoteParts.length < 3) remoteParts.add(0);

      for (int i = 0; i < 3; i++) {
        if (remoteParts[i] > currentParts[i]) return true;
        if (remoteParts[i] < currentParts[i]) return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Checks GitHub Releases API for the latest published release
  Future<AppReleaseInfo?> checkForUpdates({bool silent = false}) async {
    if (_isChecking || _isDownloading) return _latestRelease;

    _isChecking = true;
    _errorMessage = null;
    if (!silent) notifyListeners();

    try {
      final url = Uri.parse(
        'https://api.github.com/repos/$repoOwner/$repoName/releases/latest',
      );

      final response = await http.get(
        url,
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'RoomSweepSentinel-App/$currentAppVersion',
        },
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) {
        _errorMessage = 'Impossibile verificare gli aggiornamenti (HTTP ${response.statusCode})';
        _isChecking = false;
        notifyListeners();
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final tagName = data['tag_name'] as String? ?? '';
      final releaseName = data['name'] as String? ?? tagName;
      final body = data['body'] as String? ?? 'Nessuna nota di rilascio disponibile.';
      final publishedAtStr = data['published_at'] as String?;
      final publishedAt = publishedAtStr != null
          ? DateTime.tryParse(publishedAtStr) ?? DateTime.now()
          : DateTime.now();

      final assets = (data['assets'] as List<dynamic>?) ?? [];
      String apkUrl = '';
      int apkSize = 0;

      for (final asset in assets) {
        final a = asset as Map<String, dynamic>;
        final assetName = (a['name'] as String? ?? '').toLowerCase();
        if (assetName.endsWith('.apk')) {
          apkUrl = a['browser_download_url'] as String? ?? '';
          apkSize = (a['size'] as num?)?.toInt() ?? 0;
          break;
        }
      }

      final isNewer = isVersionNewer(currentAppVersion, tagName);

      _latestRelease = AppReleaseInfo(
        tagName: tagName,
        name: releaseName,
        releaseNotes: body,
        publishedAt: publishedAt,
        apkDownloadUrl: apkUrl,
        apkSizeBytes: apkSize,
        isNewerThanCurrent: isNewer,
      );

      _isChecking = false;
      notifyListeners();
      return _latestRelease;
    } catch (e) {
      debugPrint('[UpdateCheckerService] Error: $e');
      _errorMessage = 'Errore di connessione durante la verifica: $e';
      _isChecking = false;
      notifyListeners();
      return null;
    }
  }

  /// Verifies if Android OS allows requesting package installations
  Future<bool> canRequestPackageInstalls() async {
    try {
      if (!Platform.isAndroid) return false;
      final bool allowed =
          await _installerChannel.invokeMethod('canRequestPackageInstalls') ?? false;
      return allowed;
    } catch (e) {
      debugPrint('[UpdateCheckerService] canRequestPackageInstalls error: $e');
      return true;
    }
  }

  /// Opens Android settings page to grant Unknown Sources installation permission
  Future<void> openInstallPermissionSettings() async {
    try {
      if (Platform.isAndroid) {
        await _installerChannel.invokeMethod('openInstallPermissionSettings');
      }
    } catch (e) {
      debugPrint('[UpdateCheckerService] openInstallPermissionSettings error: $e');
    }
  }

  /// Downloads APK with byte-level progress reporting and launches native installer
  Future<bool> downloadAndInstallApk({
    AppReleaseInfo? release,
    void Function(double progress)? onProgress,
  }) async {
    final targetRelease = release ?? _latestRelease;
    if (targetRelease == null || targetRelease.apkDownloadUrl.isEmpty) {
      _errorMessage = 'Nessun file APK associato a questa release.';
      notifyListeners();
      return false;
    }

    if (_isDownloading) return false;

    _isDownloading = true;
    _downloadProgress = 0.0;
    _downloadedBytes = 0;
    _totalBytes = targetRelease.apkSizeBytes;
    _errorMessage = null;
    notifyListeners();

    try {
      // 1. Get safe cache directory from native Android
      final String downloadDir =
          await _installerChannel.invokeMethod('getDownloadDirectory') ?? '';
      if (downloadDir.isEmpty) {
        throw Exception('Impossibile accedere alla cartella di download.');
      }

      final safeTag = targetRelease.tagName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '');
      final apkFilePath = '$downloadDir/RoomSweepSentinel-$safeTag.apk';
      final apkFile = File(apkFilePath);

      // Clean existing old download if present
      if (await apkFile.exists()) {
        await apkFile.delete();
      }

      // 2. Stream HTTP download with progress calculation
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(targetRelease.apkDownloadUrl));
      final streamedResponse = await client.send(request);

      if (streamedResponse.statusCode != 200) {
        throw Exception('Errore download APK (HTTP ${streamedResponse.statusCode})');
      }

      final contentLength = streamedResponse.contentLength ?? targetRelease.apkSizeBytes;
      _totalBytes = contentLength;

      final sink = apkFile.openWrite();
      int received = 0;

      await for (final chunk in streamedResponse.stream) {
        sink.add(chunk);
        received += chunk.length;
        _downloadedBytes = received;

        if (contentLength > 0) {
          _downloadProgress = (received / contentLength).clamp(0.0, 1.0);
          onProgress?.call(_downloadProgress);
        }
        notifyListeners();
      }

      await sink.flush();
      await sink.close();
      client.close();

      _isDownloading = false;
      _downloadProgress = 1.0;
      notifyListeners();

      // 3. Trigger native package installer Intent
      final bool installTriggered = await _installerChannel.invokeMethod(
        'installApk',
        {'filePath': apkFilePath},
      ) ?? false;

      return installTriggered;
    } catch (e) {
      debugPrint('[UpdateCheckerService] Download error: $e');
      _errorMessage = 'Errore durante il download dell\'aggiornamento: $e';
      _isDownloading = false;
      notifyListeners();
      return false;
    }
  }

  void reset() {
    _isChecking = false;
    _isDownloading = false;
    _downloadProgress = 0.0;
    _downloadedBytes = 0;
    _errorMessage = null;
    notifyListeners();
  }
}
