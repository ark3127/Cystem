import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static const _apiKeyKey = 'nvidia_api_key';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<void> saveApiKey(String apiKey) async {
    await _storage.write(
      key: _apiKeyKey,
      value: apiKey,
    );
  }

  Future<String?> getApiKey() async {
    return await _storage.read(
      key: _apiKeyKey,
    );
  }

  Future<void> deleteApiKey() async {
    await _storage.delete(
      key: _apiKeyKey,
    );
  }

  Future<bool> hasApiKey() async {
    final apiKey = await getApiKey();
    return apiKey != null && apiKey.isNotEmpty;
  }
}
