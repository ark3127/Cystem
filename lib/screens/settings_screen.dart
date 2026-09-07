import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/app_theme_controller.dart';
import '../models/app_settings.dart';
import '../services/app_settings_service.dart';
import '../services/secure_storage_service.dart';
import '../widgets/accent_color_picker.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _apiKeyController = TextEditingController();
  final _geminiKeyController = TextEditingController();
  final _systemPromptController = TextEditingController();
  final _seedController = TextEditingController();
  final _storageService = SecureStorageService();
  final _settingsService = AppSettingsService();
  final _themeController = AppThemeController.instance;

  bool _isLoading = true;
  bool _isSaving = false;
  bool _obscureApiKey = true;
  bool _obscureGeminiKey = true;

  late AppSettings _settings;
  double _temperature = 1.0;
  String _reasoningEffort = 'high';
  int _maxTokens = 16384;
  int? _seed;
  String _themeMode = 'dark';
  Color _accentColor = AppTheme.primary;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final apiKey = await _storageService.getApiKey();
      final geminiKey = await _storageService.getGeminiApiKey();
      final settings = await _settingsService.load();
      if (!mounted) return;
      _apiKeyController.text = apiKey ?? '';
      _geminiKeyController.text = geminiKey ?? '';
      _settings = settings;
      _systemPromptController.text = settings.systemPrompt;
      _temperature = settings.temperature;
      _reasoningEffort = settings.reasoningEffort;
      _maxTokens = settings.maxTokens;
      _seed = settings.seed;
      _seedController.text = settings.seed?.toString() ?? '';
      _themeMode = settings.themeMode;
      _accentColor = Color(settings.accentColor);
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
        systemPrompt: _systemPromptController.text.trim().isEmpty
            ? AppSettings.defaultSystemPrompt
            : _systemPromptController.text.trim(),
        reasoningEffort: _reasoningEffort,
        temperature: _temperature,
        maxTokens: _maxTokens,
        seed: _seed,
        clearSeed: _seed == null,
        themeMode: _themeMode,
        accentColor: _accentColor.toARGB32(),
      );
      await _storageService.saveApiKey(apiKey);
      final geminiKey = _geminiKeyController.text.trim();
      if (geminiKey.isEmpty) {
        await _storageService.deleteGeminiApiKey();
      } else {
        await _storageService.saveGeminiApiKey(geminiKey);
      }
      await _settingsService.save(settings);
      _themeController.updateThemeMode(_themeMode);
      _themeController.updateAccentColor(_accentColor);
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

  Future<void> _deleteGeminiKey() async {
    await _storageService.deleteGeminiApiKey();
    if (mounted) {
      _geminiKeyController.clear();
      _showSnack('Gemini API key removed');
    }
  }

  Future<void> _pickAccentColor() async {
    final color = await showModalBottomSheet<Color>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: AccentColorPicker(initialColor: _accentColor),
      ),
    );
    if (color == null || !mounted) return;
    setState(() => _accentColor = color);
    _themeController.updateAccentColor(color);
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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
    _geminiKeyController.dispose();
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
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => Navigator.pop(context)),
        title: const Text('Settings'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton.filledTonal(
              onPressed: _isSaving ? null : _save,
              tooltip: 'Save settings',
              icon: _isSaving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check_rounded, size: 19),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _SectionHeader(icon: Icons.palette_outlined, title: 'Appearance', subtitle: 'Customize how CYSTEM looks'),
          _SettingsCard(children: [
            const Text('Theme', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'system', icon: Icon(Icons.brightness_auto_outlined), label: Text('System')),
                ButtonSegment(value: 'light', icon: Icon(Icons.light_mode_outlined), label: Text('Light')),
                ButtonSegment(value: 'dark', icon: Icon(Icons.dark_mode_outlined), label: Text('Dark')),
              ],
              selected: {_themeMode},
              onSelectionChanged: (selection) {
                setState(() => _themeMode = selection.first);
                _themeController.updateThemeMode(selection.first);
              },
            ),
            const SizedBox(height: 18),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(width: 42, height: 42, decoration: BoxDecoration(color: _accentColor, shape: BoxShape.circle)),
              title: const Text('Accent colour', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('#${_accentColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _pickAccentColor,
            ),
          ]),
          const SizedBox(height: 24),
          _SectionHeader(icon: Icons.auto_awesome_rounded, title: 'Model', subtitle: 'The intelligence behind CYSTEM'),
          _SettingsCard(children: [
            Row(children: [
              Container(width: 42, height: 42, decoration: BoxDecoration(color: _accentColor.withValues(alpha: .12), shape: BoxShape.circle), child: Icon(Icons.auto_awesome_rounded, color: _accentColor)),
              const SizedBox(width: 13),
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Nemotron 3 Super 120B', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                SizedBox(height: 3),
                Text('NVIDIA NIM', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
              ])),
            ]),
            const SizedBox(height: 20),
            const Text('Reasoning', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            const Text('Choose how much reasoning CYSTEM should use.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'none', label: Text('None')),
                ButtonSegment(value: 'low', label: Text('Low')),
                ButtonSegment(value: 'high', label: Text('High')),
              ],
              selected: {_reasoningEffort},
              onSelectionChanged: (selection) => setState(() => _reasoningEffort = selection.first),
            ),
          ]),
          const SizedBox(height: 14),
          _SettingsCard(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Temperature', style: TextStyle(fontWeight: FontWeight.w600)),
              Text(_temperature.toStringAsFixed(2), style: TextStyle(color: _accentColor, fontWeight: FontWeight.w600)),
            ]),
            Slider(value: _temperature, min: 0, max: 1, divisions: 20, onChanged: (value) => setState(() => _temperature = value)),
            const Text('1.0 is NVIDIA’s recommended value for Nemotron 3 Super.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            const SizedBox(height: 18),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Maximum output', style: TextStyle(fontWeight: FontWeight.w600)),
              Text('${_formatTokens(_maxTokens)} tokens', style: TextStyle(color: _accentColor, fontWeight: FontWeight.w600)),
            ]),
            Slider(value: _maxTokens.toDouble(), min: 1024, max: 32768, divisions: 31, onChanged: (value) => setState(() => _maxTokens = value.round())),
          ]),
          const SizedBox(height: 24),
          _SectionHeader(icon: Icons.visibility_outlined, title: 'Gemini', subtitle: 'Vision, image generation, editing, and Google Search'),
          _SettingsCard(children: [
            _SecretField(controller: _geminiKeyController, obscure: _obscureGeminiKey, label: 'Gemini API key', hint: 'Required for vision, image generation, and web search', onToggle: () => setState(() => _obscureGeminiKey = !_obscureGeminiKey)),
            const SizedBox(height: 8),
            const Text('Gemini is CYSTEM’s specialist layer. It understands uploaded images, generates and edits images, and powers live Google Search. Raw specialist output stays hidden unless it becomes a user-facing image or answer.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.4)),
            const SizedBox(height: 4),
            TextButton.icon(onPressed: _deleteGeminiKey, icon: const Icon(Icons.delete_outline_rounded, size: 18), label: const Text('Remove Gemini key'), style: TextButton.styleFrom(alignment: Alignment.centerLeft, padding: EdgeInsets.zero)),
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
      child: Row(children: [
        Icon(icon, size: 19, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 2),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        ])),
      ]),
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
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .45)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
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
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixIcon: IconButton(onPressed: onToggle, icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined)),
      ),
    );
  }
}
