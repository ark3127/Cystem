enum ModelTaskType {
  normalChat,
  imageUnderstanding,
  videoUnderstanding,
  audioUnderstanding,
  documentUnderstanding,
  deepReasoning,
  codeReview,
  critique,
  synthesis,
}

class ModelTask {
  final ModelTaskType type;
  final String instruction;
  final bool requiresUltra;

  const ModelTask({
    required this.type,
    required this.instruction,
    this.requiresUltra = false,
  });
}
