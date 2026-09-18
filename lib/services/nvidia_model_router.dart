import '../models/cystem_model.dart';
import 'nvidia_model_config.dart';

/// Resolves the model that should handle a request.
///
/// This is intentionally deterministic: normal chat uses Super, media
/// perception uses Nano Omni, and an explicit specialist action uses Ultra.
class NvidiaModelRouter {
  const NvidiaModelRouter();

  NvidiaModelConfig forChat() => NvidiaModelConfig.defaultModel;

  NvidiaModelConfig forMediaPerception() => NvidiaModelConfig.nanoOmni;

  NvidiaModelConfig forUltraConsultation() => NvidiaModelConfig.ultra;

  NvidiaModelConfig forModel(CystemModel model) =>
      NvidiaModelConfig.fromModel(model);
}
