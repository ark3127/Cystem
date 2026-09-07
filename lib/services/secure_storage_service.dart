import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static const _apiKeyKey = 'nvidia_api_key';
  static const _geminiApiKey = 'gemini_api_key';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<void> saveApiKey(String apiKey) async {
    await _storage.write(key: _apiKeyKey, value: apiKey);
  }

  Future<String?> getApiKey() async {
    return _storage.read(key: _apiKeyKey);
  }

  Future<void> deleteApiKey() async {
    await _storage.delete(key: _apiKeyKey);
  }

  Future<bool> hasApiKey() async {
    final apiKey = await getApiKey();
    return apiKey != null && apiKey.isNotEmpty;
  }

  Future<void> saveGeminiApiKey(String apiKey) async {
    await _storage.write(key: _geminiApiKey, value: apiKey);
  }

  Future<String?> getGeminiApiKey() async {
    return _storage.read(key: _geminiApiKey);
  }

  Future<void> deleteGeminiApiKey() async {
    await _storage.delete(key: _geminiApiKey);
  }

  Future<bool> hasGeminiApiKey() async {
    final apiKey = await getGeminiApiKey();
    return apiKey != null && apiKey.isNotEmpty;
  }
}
