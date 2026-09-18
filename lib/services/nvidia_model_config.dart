import '../models/cystem_model.dart';

/// Central configuration for the NVIDIA Nemotron models used by Cystem.
///
/// Keep model IDs in [CystemModels] and use this class when selecting a
/// model for a request. The default remains Nemotron 3 Super.
class NvidiaModelConfig {
  const NvidiaModelConfig({required this.modelId});

  final String modelId;

  static const NvidiaModelConfig superModel =
      NvidiaModelConfig(modelId: CystemModels.superModel);

  static const NvidiaModelConfig nanoOmni =
      NvidiaModelConfig(modelId: CystemModels.nanoOmni);

  static const NvidiaModelConfig ultra =
      NvidiaModelConfig(modelId: CystemModels.ultra);

  static const NvidiaModelConfig defaultModel = superModel;

  static NvidiaModelConfig fromModel(CystemModel model) {
    return switch (model) {
      CystemModel.superModel => superModel,
      CystemModel.nanoOmni => nanoOmni,
      CystemModel.ultra => ultra,
    };
  }
}
