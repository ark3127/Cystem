import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
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
  final _braveKeyController = TextEditingController();
  final _systemPromptController = TextEditingController();
  final _seedController = TextEditingController();
  final _storageService = SecureStorageService();
  final _settingsService = AppSettingsService();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _obscureApiKey = true;
  bool _obscureBraveKey = true;

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
      final braveKey = await _storageService.getBraveSearchApiKey();
      final settings = await _settingsService.load();
      if (!mounted) return;
      _apiKeyController.text = apiKey ?? '';
      _braveKeyController.text = braveKey ?? '';
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
      _showSnack('Could not load settings: $error');
    }
  }

  Future<void> _save() async {
    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty) {
      _showSnack('Add your NVIDIA API key first.');
      return;
    }
    setState(() => _isSaving = true);
    try {
      final settings = _settings.copyWith(
        systemPrompt: _systemPromptController.text.trim().isEmpty ? AppSettings.defaultSystemPrompt : _systemPromptController.text.trim(),
        reasoningEffort: _reasoningEffort,
        temperature: _temperature,
        maxTokens: _maxTokens,
        seed: _seed,
        clearSeed: _seed == null,
      );
      await _storageService.saveApiKey(apiKey);
      final braveKey = _braveKeyController.text.trim();
      if (braveKey.isEmpty) {
        await _storageService.deleteBraveSearchApiKey();
      } else {
        await _storageService.saveBraveSearchApiKey(braveKey);
      }
      await _settingsService.save(settings);
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _isSaving = false;
      });
      _showSnack('Settings saved');
    } catch (error) {
      if (mounted) {
        setState(() => _isSaving = false);
        _showSnack('Could not save settings: $error');
      }
    }
  }

  Future<void> _deleteApiKey() async {
    await _storageService.deleteApiKey();
    if (mounted) {
      _apiKeyController.clear();
      _showSnack('NVIDIA API key removed');
    }
  }

  Future<void> _deleteBraveKey() async {
    await _storageService.deleteBraveSearchApiKey();
    if (mounted) {
      _braveKeyController.clear();
      _showSnack('Web search key removed');
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
    _braveKeyController.dispose();
    _systemPromptController.dispose();
    _seedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => Navigator.pop(context)),
        title: const Text('Settings'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton.filledTonal(onPressed: _isSaving ? null : _save, tooltip: 'Save settings', icon: _isSaving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check_rounded, size: 19)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _SectionHeader(icon: Icons.auto_awesome_rounded, title: 'Model', subtitle: 'The intelligence behind CYSTEM'),
          _SettingsCard(children: [
            Row(children: [Container(width: 42, height: 42, decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.12), shape: BoxShape.circle), child: const Icon(Icons.auto_awesome_rounded, color: AppTheme.primary)), const SizedBox(width: 13), const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Nemotron 3 Super 120B', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)), SizedBox(height: 3), Text('NVIDIA NIM', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13))]))]),
            const SizedBox(height: 20),
            const Text('Reasoning', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            const Text('Choose how much reasoning CYSTEM should use.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [ButtonSegment(value: 'none', label: Text('None')), ButtonSegment(value: 'low', label: Text('Low')), ButtonSegment(value: 'high', label: Text('High'))],
              selected: {_reasoningEffort},
              onSelectionChanged: (selection) => setState(() => _reasoningEffort = selection.first),
            ),
          ]),
          const SizedBox(height: 14),
          _SettingsCard(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Temperature', style: TextStyle(fontWeight: FontWeight.w600)), Text(_temperature.toStringAsFixed(2), style: const TextStyle(color: AppTheme.primarySoft, fontWeight: FontWeight.w600))]),
            Slider(value: _temperature, min: 0, max: 1, divisions: 20, onChanged: (value) => setState(() => _temperature = value)),
            const Text('1.0 is NVIDIA’s recommended value for Nemotron 3 Super.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            const SizedBox(height: 18),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Maximum output', style: TextStyle(fontWeight: FontWeight.w600)), Text('${_formatTokens(_maxTokens)} tokens', style: const TextStyle(color: AppTheme.primarySoft, fontWeight: FontWeight.w600))]),
            Slider(value: _maxTokens.toDouble(), min: 1024, max: 32768, divisions: 31, onChanged: (value) => setState(() => _maxTokens = value.round())),
          ]),
          const SizedBox(height: 24),
          _SectionHeader(icon: Icons.language_rounded, title: 'Web search', subtitle: 'Give CYSTEM access to live search results'),
          _SettingsCard(children: [
            _SecretField(controller: _braveKeyController, obscure: _obscureBraveKey, label: 'Brave Search API key', hint: 'Optional — enables web search', onToggle: () => setState(() => _obscureBraveKey = !_obscureBraveKey)),
            const SizedBox(height: 8),
            const Text('The key is stored in Android secure storage. CYSTEM sends it only to Brave Search.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.4)),
            const SizedBox(height: 4),
            TextButton.icon(onPressed: _deleteBraveKey, icon: const Icon(Icons.delete_outline_rounded, size: 18), label: const Text('Remove search key'), style: TextButton.styleFrom(alignment: Alignment.centerLeft, padding: EdgeInsets.zero)),
          ]),
          const SizedBox(height: 24),
          _SectionHeader(icon: Icons.key_outlined, title: 'NVIDIA API', subtitle: 'Your key stays on this device'),
          _SettingsCard(children: [
            _SecretField(controller: _apiKeyController, obscure: _obscureApiKey, label: 'NVIDIA API key', hint: 'Required', onToggle: () => setState(() => _obscureApiKey = !_obscureApiKey)),
            const SizedBox(height: 4),
            TextButton.icon(onPressed: _deleteApiKey, icon: const Icon(Icons.delete_outline_rounded, size: 18), label: const Text('Remove NVIDIA key'), style: TextButton.styleFrom(alignment: Alignment.centerLeft, padding: EdgeInsets.zero)),
          ]),
          const SizedBox(height: 24),
          _SectionHeader(icon: Icons.tune_rounded, title: 'Instructions', subtitle: 'Tell CYSTEM how you want it to behave'),
          _SettingsCard(children: [
            TextField(controller: _systemPromptController, minLines: 6, maxLines: 12, maxLength: 12000, decoration: const InputDecoration(hintText: 'Your system instructions')),
          ]),
          const SizedBox(height: 24),
          _SectionHeader(icon: Icons.science_outlined, title: 'Advanced', subtitle: 'Optional deterministic generation control'),
          _SettingsCard(children: [
            TextField(controller: _seedController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Seed', hintText: 'Optional'), onChanged: (value) => setState(() => _seed = int.tryParse(value.trim()))),
          ]),
          const SizedBox(height: 24),
          FilledButton.icon(onPressed: _isSaving ? null : _save, icon: const Icon(Icons.check_rounded), label: Text(_isSaving ? 'Saving…' : 'Save settings'), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusMedium)))),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
      child: Row(children: [Icon(icon, size: 19, color: AppTheme.primary), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: Theme.of(context).textTheme.titleMedium), const SizedBox(height: 2), Text(subtitle, style: Theme.of(context).textTheme.bodySmall)]))]),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(AppTheme.radiusMedium)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }
}

class _SecretField extends StatelessWidget {
  const _SecretField({required this.controller, required this.obscure, required this.label, required this.hint, required this.onToggle});
  final TextEditingController controller;
  final bool obscure;
  final String label;
  final String hint;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(labelText: label, hintText: hint, prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20), suffixIcon: IconButton(icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined), onPressed: onToggle)),
    );
  }
}
