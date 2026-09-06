class AppSettings {
  static const String defaultSystemPrompt =
      'You are Cystem, a helpful personal AI assistant. Be accurate, clear, and practical.';

  final String systemPrompt;
  final String reasoningEffort;
  final double temperature;
  final int maxTokens;
  final int? seed;

  const AppSettings({
    this.systemPrompt = defaultSystemPrompt,
    this.reasoningEffort = 'max',
    this.temperature = 1.0,
    this.maxTokens = 16384,
    this.seed,
  });

  AppSettings copyWith({
    String? systemPrompt,
    String? reasoningEffort,
    double? temperature,
    int? maxTokens,
    int? seed,
    bool clearSeed = false,
  }) {
    return AppSettings(
      systemPrompt: systemPrompt ?? this.systemPrompt,
      reasoningEffort: reasoningEffort ?? this.reasoningEffort,
      temperature: temperature ?? this.temperature,
      maxTokens: maxTokens ?? this.maxTokens,
      seed: clearSeed ? null : (seed ?? this.seed),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'systemPrompt': systemPrompt,
      'reasoningEffort': reasoningEffort,
      'temperature': temperature,
      'maxTokens': maxTokens,
      if (seed != null) 'seed': seed,
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final temperature = (json['temperature'] as num?)?.toDouble();
    final maxTokens = (json['maxTokens'] as num?)?.toInt();
    final seed = (json['seed'] as num?)?.toInt();
    final reasoningEffort = json['reasoningEffort'];
    final systemPrompt = json['systemPrompt'];

    return AppSettings(
      systemPrompt: systemPrompt is String
          ? systemPrompt
          : defaultSystemPrompt,
      reasoningEffort: reasoningEffort is String &&
              const ['low', 'high', 'max'].contains(reasoningEffort)
          ? reasoningEffort
          : 'max',
      temperature: temperature == null
          ? 1.0
          : temperature.clamp(0.0, 1.0).toDouble(),
      maxTokens: maxTokens == null
          ? 16384
          : maxTokens.clamp(1, 65536),
      seed: seed,
    );
  }
}
