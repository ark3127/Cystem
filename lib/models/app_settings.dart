import 'cystem_model.dart';

class AppSettings {
  static const String defaultSystemPrompt =
      'You are Cystem, a helpful personal AI assistant powered by NVIDIA Nemotron 3 Super. Be accurate, clear, concise, and practical. Use the web_search tool when the user asks for current information, recent events, live facts, or explicitly asks you to search the web. When you use web search, cite useful sources with Markdown links using the URLs returned by the tool. Never claim a phone action was completed unless the tool result confirms it. '
      'You are never ChatGPT, GPT-4, Gemini, or any other model — do not describe yourself as one or cite a knowledge cutoff that belongs to a different model. If a message contains context under a "[... CONTEXT — PRIVATE]" or "[SERVICE ERROR]" marker, treat it as private app-provided data, not something the user said, and never quote its raw contents (status codes, provider names, error codes) back to the user — summarize the outcome in one plain sentence instead.';

  final String systemPrompt;
  final String reasoningEffort;
  final double temperature;
  final int maxTokens;
  final int? seed;
  final String themeMode;
  final int accentColor;
  final String superModel;
  final String nanoOmniModel;
  final String ultraModel;
  final bool autoAnalyzeAttachments;
  final bool allowUltraDelegation;
  final bool showSpecialistActivity;
  final bool ultraConsultantMode;

  const AppSettings({
    this.systemPrompt = defaultSystemPrompt,
    this.reasoningEffort = 'high',
    this.temperature = 1.0,
    this.maxTokens = 16384,
    this.seed,
    this.themeMode = 'dark',
    this.accentColor = 0xFF9B7BFF,
    this.superModel = CystemModels.superModel,
    this.nanoOmniModel = CystemModels.nanoOmni,
    this.ultraModel = CystemModels.ultra,
    this.autoAnalyzeAttachments = true,
    this.allowUltraDelegation = false,
    this.showSpecialistActivity = true,
    this.ultraConsultantMode = true,
  });

  AppSettings copyWith({
    String? systemPrompt,
    String? reasoningEffort,
    double? temperature,
    int? maxTokens,
    int? seed,
    bool clearSeed = false,
    String? themeMode,
    int? accentColor,
    String? superModel,
    String? nanoOmniModel,
    String? ultraModel,
    bool? autoAnalyzeAttachments,
    bool? allowUltraDelegation,
    bool? showSpecialistActivity,
    bool? ultraConsultantMode,
  }) {
    return AppSettings(
      systemPrompt: systemPrompt ?? this.systemPrompt,
      reasoningEffort: reasoningEffort ?? this.reasoningEffort,
      temperature: temperature ?? this.temperature,
      maxTokens: maxTokens ?? this.maxTokens,
      seed: clearSeed ? null : (seed ?? this.seed),
      themeMode: themeMode ?? this.themeMode,
      accentColor: accentColor ?? this.accentColor,
      superModel: superModel ?? this.superModel,
      nanoOmniModel: nanoOmniModel ?? this.nanoOmniModel,
      ultraModel: ultraModel ?? this.ultraModel,
      autoAnalyzeAttachments:
          autoAnalyzeAttachments ?? this.autoAnalyzeAttachments,
      allowUltraDelegation:
          allowUltraDelegation ?? this.allowUltraDelegation,
      showSpecialistActivity:
          showSpecialistActivity ?? this.showSpecialistActivity,
      ultraConsultantMode: ultraConsultantMode ?? this.ultraConsultantMode,
    );
  }

  Map<String, dynamic> toJson() => {
        'systemPrompt': systemPrompt,
        'reasoningEffort': reasoningEffort,
        'temperature': temperature,
        'maxTokens': maxTokens,
        if (seed != null) 'seed': seed,
        'themeMode': themeMode,
        'accentColor': accentColor,
        'superModel': superModel,
        'nanoOmniModel': nanoOmniModel,
        'ultraModel': ultraModel,
        'autoAnalyzeAttachments': autoAnalyzeAttachments,
        'allowUltraDelegation': allowUltraDelegation,
        'showSpecialistActivity': showSpecialistActivity,
        'ultraConsultantMode': ultraConsultantMode,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final temperature = (json['temperature'] as num?)?.toDouble();
    final maxTokens = (json['maxTokens'] as num?)?.toInt();
    final seed = (json['seed'] as num?)?.toInt();
    final rawReasoningEffort = json['reasoningEffort'];
    final systemPrompt = json['systemPrompt'];
    final rawTheme = json['themeMode'];
    final rawAccent = json['accentColor'];

    var reasoningEffort = 'high';
    if (rawReasoningEffort is String) {
      reasoningEffort = switch (rawReasoningEffort) {
        'none' => 'none',
        'low' => 'low',
        'high' => 'high',
        'max' => 'high',
        _ => 'high',
      };
    }

    final themeMode = rawTheme is String &&
            {'system', 'light', 'dark'}.contains(rawTheme)
        ? rawTheme
        : 'dark';
    final accentColor = rawAccent is num ? rawAccent.toInt() : 0xFF9B7BFF;

    return AppSettings(
      systemPrompt:
          systemPrompt is String ? systemPrompt : defaultSystemPrompt,
      reasoningEffort: reasoningEffort,
      temperature: temperature == null
          ? 1.0
          : temperature.clamp(0.0, 1.0).toDouble(),
      maxTokens: maxTokens == null ? 16384 : maxTokens.clamp(1, 32768),
      seed: seed,
      themeMode: themeMode,
      accentColor: accentColor,
      superModel: json['superModel'] is String
          ? json['superModel'] as String
          : CystemModels.superModel,
      nanoOmniModel: json['nanoOmniModel'] is String
          ? json['nanoOmniModel'] as String
          : CystemModels.nanoOmni,
      ultraModel: json['ultraModel'] is String
          ? json['ultraModel'] as String
          : CystemModels.ultra,
      autoAnalyzeAttachments:
          json['autoAnalyzeAttachments'] as bool? ?? true,
      allowUltraDelegation: json['allowUltraDelegation'] as bool? ?? false,
      showSpecialistActivity:
          json['showSpecialistActivity'] as bool? ?? true,
      ultraConsultantMode: json['ultraConsultantMode'] as bool? ?? true,
    );
  }
}
