import 'package:code_note/features/ai/ai_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('settings survive saving and loading', () {
    const s = AiSettings(
      enabled: true,
      provider: AiProvider.ollama,
      model: 'llama3',
      baseUrl: 'http://192.168.1.5:11434/',
    );
    final back = AiSettings.fromJson(s.toJson());
    expect(back.provider, AiProvider.ollama);
    expect(back.effectiveModel, 'llama3');
    expect(back.effectiveBaseUrl, 'http://192.168.1.5:11434');
  });

  test('ready only when enabled and, if needed, a key is set', () {
    expect(const AiSettings(enabled: true).isReady, isFalse); // Claude needs a key
    expect(const AiSettings(enabled: true, apiKey: 'k').isReady, isTrue);
    expect(const AiSettings(enabled: true, provider: AiProvider.ollama).isReady, isTrue);
    expect(const AiSettings(apiKey: 'k').isReady, isFalse); // switched off
  });

  test('empty model and address use the provider defaults', () {
    const s = AiSettings(provider: AiProvider.claude);
    expect(s.effectiveModel, AiProvider.claude.defaultModel);
    expect(s.effectiveBaseUrl, 'https://api.anthropic.com');
  });

  test('prompts include the language and the code', () {
    final p = AiAction.explain.prompt('Python', 'print(1)');
    expect(p, contains('Python'));
    expect(p, contains('print(1)'));
  });

  test('LM Studio and other local servers need no key', () {
    const lm = AiSettings(
      enabled: true,
      provider: AiProvider.openAiCompatible,
      baseUrl: 'http://localhost:1234',
    );
    expect(lm.isLocal, isTrue);
    expect(lm.isReady, isTrue);
    const cloud = AiSettings(enabled: true, provider: AiProvider.openAiCompatible);
    expect(cloud.isLocal, isFalse);
    expect(cloud.isReady, isFalse);
  });
}
