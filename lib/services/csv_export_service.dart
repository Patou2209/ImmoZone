import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CsvExportService
//
// Saves a CSV string to the Downloads directory on Android, then shares it
// via the system share sheet. On web the caller must handle the download.
// On iOS uses the temp directory + share sheet.
//
// Usage:
//   await CsvExportService.export(csvContent: '...', fileName: 'stats.csv');
// ─────────────────────────────────────────────────────────────────────────────
class CsvExportService {
  /// Exports [csvContent] as [fileName] to local storage.
  /// Returns the file path on success, or null on failure.
  static Future<String?> export({
    required String csvContent,
    required String fileName,
  }) async {
    if (kIsWeb) {
      // Web: not supported here — caller should use web-specific download
      return null;
    }

    try {
      Directory dir;

      if (Platform.isAndroid) {
        // Try Downloads folder first (visible in file manager)
        try {
          dir = Directory('/storage/emulated/0/Download');
          if (!await dir.exists()) {
            dir = await getTemporaryDirectory();
          }
        } catch (_) {
          dir = await getTemporaryDirectory();
        }
      } else {
        // iOS / others: use temp dir + share
        dir = await getTemporaryDirectory();
      }

      final file = File('${dir.path}/$fileName');
      await file.writeAsString(csvContent, flush: true);

      // Share via system share sheet (user can save to Drive, email, etc.)
      final xFile = XFile(file.path, mimeType: 'text/csv', name: fileName);
      final result = await Share.shareXFiles(
        [xFile],
        subject: fileName.replaceAll('.csv', '').replaceAll('_', ' '),
        text: 'Export CSV ImmoZone',
      );

      if (result.status == ShareResultStatus.dismissed) {
        // User dismissed — file still saved locally on Android
        return file.path;
      }
      return file.path;
    } catch (e) {
      if (kDebugMode) debugPrint('[CsvExportService] Erreur: $e');
      return null;
    }
  }

  // ─── Helpers pour formater les valeurs CSV ─────────────────────────────────

  /// Entoure de guillemets et échappe les guillemets internes.
  static String q(String? value) {
    if (value == null || value.isEmpty) return '""';
    final escaped = value.replaceAll('"', '""');
    return '"$escaped"';
  }

  /// Formate une DateTime en dd/MM/yyyy HH:mm.
  static String fmtDateTime(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    return '$d/$mo/${dt.year} $h:$mi';
  }

  /// Formate une DateTime en dd/MM/yyyy.
  static String fmtDate(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    return '$d/$mo/${dt.year}';
  }

  /// Formate un montant avec 2 décimales.
  static String fmtAmount(double v) => v.toStringAsFixed(2);

  /// Génère un nom de fichier avec timestamp.
  static String fileName(String prefix) {
    final now = DateTime.now();
    final ts =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}'
        '_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    return '${prefix}_$ts.csv';
  }
}
