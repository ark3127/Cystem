/// Background execution is intentionally disabled for normal chat generation.
///
/// The previous implementation requested Android's "always run in the
/// background" permission on every generation, which is intrusive for a
/// personal foreground chat app. Keep this small compatibility service so
/// older callers can remain harmlessly no-op.
class BackgroundExecutionService {
  Future<void> start() async {}
  Future<void> stop() async {}
}
