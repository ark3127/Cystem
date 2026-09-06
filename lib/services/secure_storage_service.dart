import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static const _apiKeyKey = 'nvidia_api_key';
  static const _braveSearchApiKey = 'brave_search_api_key';

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

  Future<void> saveBraveSearchApiKey(String apiKey) async {
    await _storage.write(key: _braveSearchApiKey, value: apiKey);
  }

  Future<String?> getBraveSearchApiKey() async {
    return _storage.read(key: _braveSearchApiKey);
  }

  Future<void> deleteBraveSearchApiKey() async {
    await _storage.delete(key: _braveSearchApiKey);
  }

  Future<bool> hasBraveSearchApiKey() async {
    final apiKey = await getBraveSearchApiKey();
    return apiKey != null && apiKey.isNotEmpty;
  }
}
