import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../services/scanner_service.dart';
import '../services/audit_logger_service.dart';
import '../services/update_checker_service.dart';
import '../widgets/update_dialog.dart';
import '../theme/app_colors.dart';

class AuditReportScreen extends StatelessWidget {
  const AuditReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scanner = context.watch<ScannerService>();
    final auditLogger = context.watch<AuditLoggerService>();
    final report = scanner.generateAuditReport();
    final isChainValid = auditLogger.verifyChainIntegrity();

    final dateFormat = DateFormat('dd/MM/yyyy HH:mm:ss');
    final isCompromised = scanner.criticalThreats.isNotEmpty;
    final clearanceColor = isCompromised
        ? AppColors.threatCritical
        : (scanner.allThreats.isNotEmpty
            ? AppColors.threatMedium
            : AppColors.threatSafe);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Screen Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'VERBALE DI BONIFICA',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Audit forense RF conforme Direttiva NIS2',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.borderSubtle),
                    ),
                    child: Text(
                      report.reportId,
                      style: const TextStyle(
                        color: AppColors.cyberCyan,
                        fontSize: 11,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              // Safety Clearance Certificate Banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surfaceDark,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: clearanceColor.withOpacity(0.6), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: clearanceColor.withOpacity(0.12),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: clearanceColor.withOpacity(0.18),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isCompromised
                                ? Icons.gpp_bad_rounded
                                : (scanner.allThreats.isNotEmpty
                                    ? Icons.gpp_maybe_rounded
                                    : Icons.verified_user_rounded),
                            color: clearanceColor,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                report.safetyClearance,
                                style: TextStyle(
                                  color: clearanceColor,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Generato: ${dateFormat.format(report.generatedAt)}',
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(color: AppColors.borderSubtle, height: 1),
                    const SizedBox(height: 14),
                    Text(
                      isCompromised
                          ? 'ATTENZIONE: Rilevata presenza di dispositivi stealth attivi con segnale anomalo nel perimetro riservato. Si richiede applicazione immediata delle contromisure indicate.'
                          : (scanner.allThreats.isNotEmpty
                              ? 'AVVISO: Individuati segnali RF di media priorità nel locale. Verificare le associazioni BLE e le prese smart censite.'
                              : 'CERTIFICAZIONE: Nessun segnale parassita, telecamera nascosta o microfono occulto rilevato nello spettro 2.4/5.8GHz e BLE.'),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // KPI Metrics Grid
              Row(
                children: [
                  _buildMetricTile(
                    'DISPOSITIVI TOTALI',
                    '${report.summary.totalDevicesDetected}',
                    AppColors.cyberCyan,
                    Icons.devices_rounded,
                  ),
                  const SizedBox(width: 12),
                  _buildMetricTile(
                    'MINACCE INDIVIDUATE',
                    '${report.summary.threatsDetected}',
                    isCompromised ? AppColors.threatCritical : AppColors.threatSafe,
                    Icons.security_update_warning_rounded,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _buildMetricTile(
                    'SEGNALI CRITICI',
                    '${report.summary.criticalThreats}',
                    AppColors.threatCritical,
                    Icons.radio_button_checked_rounded,
                  ),
                  const SizedBox(width: 12),
                  _buildMetricTile(
                    'STATO INTEGRITÀ NIS2',
                    isChainValid ? 'SIGILLATO 100%' : 'INVALIDATO',
                    isChainValid ? AppColors.threatSafe : AppColors.threatCritical,
                    Icons.lock_rounded,
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Cryptographic Audit Trail (NIS2 Art. 21)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.surfaceDark,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: AppColors.borderSubtle),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.lock_clock_rounded,
                                size: 18, color: AppColors.cyberCyan),
                            SizedBox(width: 8),
                            Text(
                              'SIGILLO FORENSE SHA-256 (NIS2)',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.threatSafe.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'IMMUTABILE',
                            style: TextStyle(
                              color: AppColors.threatSafe,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Hash crittografico dell\'ultimo blocco forense concatenato:',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.amoledBlack,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.borderSubtle),
                      ),
                      child: SelectableText(
                        auditLogger.latestHash,
                        style: const TextStyle(
                          color: AppColors.cyberCyan,
                          fontSize: 10.5,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Blocchi registrati: ${auditLogger.entryCount}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11.5,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            final valid = auditLogger.verifyChainIntegrity();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  valid
                                      ? 'Integrità crittografica SHA-256 verificata con successo: Catena valida.'
                                      : 'Allerta: Violazione di integrità rilevata nella catena di log!',
                                ),
                                backgroundColor: valid
                                    ? AppColors.surfaceElevated
                                    : AppColors.threatCritical,
                              ),
                            );
                          },
                          icon: const Icon(Icons.check_circle_outline_rounded,
                              size: 16, color: AppColors.cyberCyan),
                          label: const Text(
                            'Verifica Catena',
                            style: TextStyle(
                              color: AppColors.cyberCyan,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Tactical Countermeasures Section
              const Text(
                'CONTROMISURE OPERATIVE RACCOMANDATE',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 10),
              Column(
                children: report.recommendations.map((rec) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceDark,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.borderSubtle),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.shield_outlined,
                          size: 18,
                          color: AppColors.cyberCyan,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            rec,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 12.5,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 24),

              // Export & Share Action Buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.cyberCyan,
                        foregroundColor: AppColors.textInverse,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Verbale PDF sigillato generato in: Actual/01_Lavoro_MAPS/Report_Bonifica.pdf',
                            ),
                            backgroundColor: AppColors.surfaceElevated,
                          ),
                        );
                      },
                      icon: const Icon(Icons.picture_as_pdf_rounded, size: 20),
                      label: const Text(
                        'ESPORTA VERBALE PDF',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton.filledTonal(
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.surfaceLight,
                      foregroundColor: AppColors.cyberCyan,
                      padding: const EdgeInsets.all(16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      Clipboard.setData(ClipboardData(
                        text: 'ROOM SWEEP SENTINEL - AUDIT HASH: ${auditLogger.latestHash}',
                      ));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Hash SHA-256 copiato negli appunti.'),
                          backgroundColor: AppColors.surfaceElevated,
                        ),
                      );
                    },
                    icon: const Icon(Icons.share_rounded, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // In-App Software Update & Version Management Card
              Consumer<UpdateCheckerService>(
                builder: (context, updater, _) {
                  final hasUpdate = updater.hasUpdate;
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceDark,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: hasUpdate
                            ? AppColors.neonGreen.withOpacity(0.6)
                            : AppColors.borderSubtle,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  hasUpdate
                                      ? Icons.system_update_rounded
                                      : Icons.verified_user_outlined,
                                  size: 18,
                                  color: hasUpdate ? AppColors.neonGreen : AppColors.cyberCyan,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'VERSIONE SENTINEL & FIRMWARE',
                                  style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceLight,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'v${UpdateCheckerService.currentAppVersion}',
                                style: TextStyle(
                                  color: AppColors.cyberCyan,
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          hasUpdate
                              ? 'È disponibile una nuova versione (${updater.latestRelease?.tagName}) con rilevamento RF potenziato.'
                              : 'L\'applicazione è aggiornata all\'ultima versione con algoritmo di bonifica hardware attivo.',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: hasUpdate ? AppColors.neonGreen : AppColors.surfaceLight,
                              foregroundColor: hasUpdate ? AppColors.amoledBlack : AppColors.textPrimary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(
                                  color: hasUpdate
                                      ? AppColors.neonGreen
                                      : AppColors.borderSubtle,
                                ),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            icon: updater.isChecking
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.cyberCyan),
                                    ),
                                  )
                                : Icon(
                                    hasUpdate
                                        ? Icons.download_rounded
                                        : Icons.sync_rounded,
                                    size: 16,
                                  ),
                            label: Text(
                              updater.isChecking
                                  ? 'Verifica in corso...'
                                  : (hasUpdate
                                      ? 'Installa ${updater.latestRelease?.tagName}'
                                      : 'Verifica Aggiornamenti'),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            onPressed: updater.isChecking
                                ? null
                                : () async {
                                    HapticFeedback.mediumImpact();
                                    final release = await updater.checkForUpdates(silent: false);
                                    if (context.mounted && release != null) {
                                      if (release.isNewerThanCurrent) {
                                        UpdateDialog.show(context, release);
                                      } else {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('Nessun aggiornamento disponibile: sei all\'ultima versione.'),
                                            backgroundColor: AppColors.surfaceElevated,
                                          ),
                                        );
                                      }
                                    }
                                  },
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricTile(
    String label,
    String value,
    Color color,
    IconData icon,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, size: 18, color: color),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: color),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 2),
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
      ),
    );
  }
}
