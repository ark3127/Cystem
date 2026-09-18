enum CystemModel {
  superModel,
  nanoOmni,
  ultra,
}

class CystemModels {
  static const String superModel =
      'nvidia/nemotron-3-super-120b-a12b';

  static const String nanoOmni =
      'nvidia/nemotron-3-nano-omni-30b-a3b-reasoning';

  static const String ultra =
      'nvidia/nemotron-3-ultra-550b-a55b';

  static String idFor(CystemModel model) {
    return switch (model) {
      CystemModel.superModel => superModel,
      CystemModel.nanoOmni => nanoOmni,
      CystemModel.ultra => ultra,
    };
  }

  static String displayName(CystemModel model) {
    return switch (model) {
      CystemModel.superModel => 'Nemotron 3 Super',
      CystemModel.nanoOmni => 'Nemotron 3 Nano Omni',
      CystemModel.ultra => 'Nemotron 3 Ultra',
    };
  }
}
