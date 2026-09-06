import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../services/app_settings_service.dart';
import '../services/secure_storage_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _apiKeyController = TextEditingController();
  final _systemPromptController = TextEditingController();
  final _seedController = TextEditingController();
  final _storageService = SecureStorageService();
  final _settingsService = AppSettingsService();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _obscureApiKey = true;

  late AppSettings _settings;
  double _temperature = 1.0;
  String _reasoningEffort = 'high';
  int _maxTokens = 16384;
  int? _seed;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final apiKey = await _storageService.getApiKey();
      final settings = await _settingsService.load();
      if (!mounted) return;
      _apiKeyController.text = apiKey ?? '';
      _settings = settings;
      _systemPromptController.text = settings.systemPrompt;
      _temperature = settings.temperature;
      _reasoningEffort = settings.reasoningEffort;
      _maxTokens = settings.maxTokens;
      _seed = settings.seed;
      _seedController.text = settings.seed?.toString() ?? '';
      setState(() => _isLoading = false);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load settings: $error')),
      );
    }
  }

  Future<void> _save() async {
    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an API key.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final settings = _settings.copyWith(
        systemPrompt: _systemPromptController.text.trim().isEmpty
            ? AppSettings.defaultSystemPrompt
            : _systemPromptController.text.trim(),
        reasoningEffort: _reasoningEffort,
        temperature: _temperature,
        maxTokens: _maxTokens,
        seed: _seed,
        clearSeed: _seed == null,
      );

      await _storageService.saveApiKey(apiKey);
      await _settingsService.save(settings);
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _systemPromptController.text = settings.systemPrompt;
        _seedController.text = settings.seed?.toString() ?? '';
        _isSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save settings: $error')),
      );
    }
  }

  Future<void> _deleteApiKey() async {
    try {
      await _storageService.deleteApiKey();
      if (!mounted) return;
      setState(() => _apiKeyController.clear());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('API key removed.')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not remove API key: $error')),
        );
      }
    }
  }

  String _formatTokens(int value) {
    if (value >= 1000) {
      final thousands = value / 1000;
      return '${thousands.toStringAsFixed(thousands % 1 == 0 ? 0 : 1)}k';
    }
    return value.toString();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _systemPromptController.dispose();
    _seedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Nemotron 3 Super 120B', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('Powered by NVIDIA NIM.'),
          const SizedBox(height: 28),
          Text('NVIDIA API Key', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('Your API key is stored securely on this device.'),
          const SizedBox(height: 16),
          TextField(
            controller: _apiKeyController,
            obscureText: _obscureApiKey,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'API Key',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscureApiKey ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscureApiKey = !_obscureApiKey),
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: _deleteApiKey, child: const Text('Remove API Key')),
          const SizedBox(height: 32),
          Text('Reasoning', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('Nemotron supports no reasoning, low-effort reasoning, or full reasoning.'),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'none', label: Text('Off')),
              ButtonSegment(value: 'low', label: Text('Low')),
              ButtonSegment(value: 'high', label: Text('High')),
            ],
            selected: {_reasoningEffort},
            onSelectionChanged: (selection) => setState(() => _reasoningEffort = selection.first),
          ),
          const SizedBox(height: 28),
          Text('Temperature  ${_temperature.toStringAsFixed(2)}', style: Theme.of(context).textTheme.titleMedium),
          Slider(
            value: _temperature,
            min: 0,
            max: 1,
            divisions: 20,
            label: _temperature.toStringAsFixed(2),
            onChanged: (value) => setState(() => _temperature = value),
          ),
          const Text('NVIDIA recommends 1.0 for Nemotron 3 Super.'),
          const SizedBox(height: 24),
          Text('Maximum output  ${_formatTokens(_maxTokens)} tokens', style: Theme.of(context).textTheme.titleMedium),
          Slider(
            value: _maxTokens.toDouble(),
            min: 1024,
            max: 32768,
            divisions: 31,
            label: _maxTokens.toString(),
            onChanged: (value) => setState(() => _maxTokens = value.round()),
          ),
          const Text('Maximum generated output. Nemotron 3 Super supports up to 32,768 tokens.'),
          const SizedBox(height: 28),
          Text('System instructions', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('Instructions sent to Nemotron as the system message on every request.'),
          const SizedBox(height: 12),
          TextField(
            controller: _systemPromptController,
            minLines: 5,
            maxLines: 10,
            maxLength: 12000,
            decoration: const InputDecoration(
              hintText: 'Tell Cystem how it should behave...',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 28),
          Text('Advanced', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('Seed is optional. Leave it empty for normal model behavior.'),
          const SizedBox(height: 12),
          TextField(
            controller: _seedController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Seed',
              hintText: 'Optional',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) {
              final parsed = int.tryParse(value.trim());
              setState(() => _seed = parsed);
            },
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save Settings'),
          ),
        ],
      ),
    );
  }
}
