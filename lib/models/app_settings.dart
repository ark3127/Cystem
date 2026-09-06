class AppSettings {
  static const String defaultSystemPrompt =
      'You are Cystem, a helpful personal AI assistant powered by NVIDIA Nemotron 3 Super. Be accurate, clear, concise, and practical. Use the web_search tool when the user asks for current information, recent events, live facts, or explicitly asks you to search the web. When you use web search, cite useful sources with Markdown links using the URLs returned by the tool. Never claim a phone action was completed unless the tool result confirms it.';

  final String systemPrompt;
  final String reasoningEffort;
  final double temperature;
  final int maxTokens;
  final int? seed;

  const AppSettings({this.systemPrompt = defaultSystemPrompt, this.reasoningEffort = 'high', this.temperature = 1.0, this.maxTokens = 16384, this.seed});

  AppSettings copyWith({String? systemPrompt, String? reasoningEffort, double? temperature, int? maxTokens, int? seed, bool clearSeed = false}) {
    return AppSettings(systemPrompt: systemPrompt ?? this.systemPrompt, reasoningEffort: reasoningEffort ?? this.reasoningEffort, temperature: temperature ?? this.temperature, maxTokens: maxTokens ?? this.maxTokens, seed: clearSeed ? null : (seed ?? this.seed));
  }

  Map<String, dynamic> toJson() => {
        'systemPrompt': systemPrompt,
        'reasoningEffort': reasoningEffort,
        'temperature': temperature,
        'maxTokens': maxTokens,
        if (seed != null) 'seed': seed,
      };

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
        'max' => 'high',
        _ => 'high',
      };
    }

    return AppSettings(
      systemPrompt: systemPrompt is String ? systemPrompt : defaultSystemPrompt,
      reasoningEffort: reasoningEffort,
      temperature: temperature == null ? 1.0 : temperature.clamp(0.0, 1.0).toDouble(),
      maxTokens: maxTokens == null ? 16384 : maxTokens.clamp(1, 32768),
      seed: seed,
    );
  }
}
