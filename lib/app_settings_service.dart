import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/app_settings.dart';

class AppSettingsService {
  static const String _fileName = 'cystem_settings.json';

  Future<File> _getSettingsFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_fileName');
  }

  Future<AppSettings> load() async {
    try {
      final file = await _getSettingsFile();
      if (!await file.exists()) {
        return const AppSettings();
      }

      final contents = await file.readAsString();
      if (contents.trim().isEmpty) {
        return const AppSettings();
      }

      final decoded = jsonDecode(contents);
      if (decoded is! Map) {
        return const AppSettings();
      }

      return AppSettings.fromJson(
        Map<String, dynamic>.from(decoded),
      );
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<void> save(AppSettings settings) async {
    final file = await _getSettingsFile();
    await file.writeAsString(
      jsonEncode(settings.toJson()),
      flush: true,
    );
  }
}
