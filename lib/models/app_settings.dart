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
    this.reasoningEffort = 'high',
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
    final rawReasoningEffort = json['reasoningEffort'];
    final systemPrompt = json['systemPrompt'];

    var reasoningEffort = 'high';
    if (rawReasoningEffort is String) {
      reasoningEffort = switch (rawReasoningEffort) {
        'none' => 'none',
        'low' => 'low',
        'high' => 'high',
        // Migrate the old Kimi K3 setting to Nemotron's full reasoning mode.
        'max' => 'high',
        _ => 'high',
      };
    }

    return AppSettings(
      systemPrompt: systemPrompt is String
          ? systemPrompt
          : defaultSystemPrompt,
      reasoningEffort: reasoningEffort,
      temperature: temperature == null
          ? 1.0
          : temperature.clamp(0.0, 1.0).toDouble(),
      maxTokens: maxTokens == null
          ? 16384
          : maxTokens.clamp(1, 32768),
      seed: seed,
    );
  }
}
