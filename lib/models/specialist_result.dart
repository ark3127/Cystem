import 'cystem_model.dart';

class SpecialistResult {
  final CystemModel model;
  final String content;
  final String? task;
  final bool successful;
  final String? error;

  const SpecialistResult({
    required this.model,
    required this.content,
    this.task,
    this.successful = true,
    this.error,
  });

  factory SpecialistResult.failure({
    required CystemModel model,
    required String error,
    String? task,
  }) {
    return SpecialistResult(
      model: model,
      content: '',
      task: task,
      successful: false,
      error: error,
    );
  }
}
