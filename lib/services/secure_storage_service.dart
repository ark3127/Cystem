import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  SecureStorageService._();

  static const _storage = FlutterSecureStorage();

  static const _apiKeyKey = 'nvidia_api_key';

  static Future<void> saveApiKey(String apiKey) async {
    await _storage.write(
      key: _apiKeyKey,
      value: apiKey.trim(),
    );
  }

  static Future<String?> getApiKey() async {
    return _storage.read(key: _apiKeyKey);
  }

  static Future<void> deleteApiKey() async {
    await _storage.delete(key: _apiKeyKey);
  }

  static Future<bool> hasApiKey() async {
    final apiKey = await getApiKey();
    return apiKey != null && apiKey.isNotEmpty;
  }
}
