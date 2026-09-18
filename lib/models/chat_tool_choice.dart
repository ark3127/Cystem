/// Controls whether Kimi K3 may or must call a tool.
class ChatToolChoice {
  final String mode;
  final String? toolName;

  const ChatToolChoice._(this.mode, this.toolName);

  const ChatToolChoice.none() : this._('none', null);
  const ChatToolChoice.auto() : this._('auto', null);
  const ChatToolChoice.required() : this._('required', null);
  const ChatToolChoice.named(String name) : this._('named', name);

  dynamic toApiJson() {
    switch (mode) {
      case 'named':
        return {
          'type': 'function',
          'function': {'name': toolName},
        };
      default:
        return mode;
    }
  }
}
