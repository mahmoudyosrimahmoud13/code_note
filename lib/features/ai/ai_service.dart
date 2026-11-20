import 'dart:async';
import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

/// Where AI requests go.
enum AiProvider { claude, openAiCompatible, ollama }

extension AiProviderInfo on AiProvider {
  String get label => switch (this) {
        AiProvider.claude => 'Claude',
        AiProvider.openAiCompatible => 'OpenAI-compatible',
        AiProvider.ollama => 'Ollama (local)',
      };

  String get defaultModel => switch (this) {
        AiProvider.claude => 'claude-sonnet-5-5',
        AiProvider.openAiCompatible => 'gpt-4o-mini',
        AiProvider.ollama => 'qwen2.5-coder',
      };

  String get defaultBaseUrl => switch (this) {
        AiProvider.claude => 'https://api.anthropic.com',
        AiProvider.openAiCompatible => 'https://api.openai.com',
        AiProvider.ollama => 'http://localhost:11434',
      };

  bool get needsKey => this != AiProvider.ollama;
}

/// AI settings. Saved only on this device, in their own storage box, so
/// they're never part of notes, shares or exports.
class AiSettings {
  const AiSettings({
    this.enabled = false,
    this.provider = AiProvider.claude,
    this.apiKey = '',
    this.model = '',
    this.baseUrl = '',
  });

  final bool enabled;
  final AiProvider provider;
  final String apiKey;
  final String model;
  final String baseUrl;

  String get effectiveModel => model.trim().isEmpty ? provider.defaultModel : model.trim();
  String get effectiveBaseUrl {
    final url = baseUrl.trim().isEmpty ? provider.defaultBaseUrl : baseUrl.trim();
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  /// Ready to send requests.
  bool get isReady => enabled && (!provider.needsKey || apiKey.trim().isNotEmpty);

  AiSettings copyWith({
    bool? enabled,
    AiProvider? provider,
    String? apiKey,
    String? model,
    String? baseUrl,
  }) =>
      AiSettings(
        enabled: enabled ?? this.enabled,
        provider: provider ?? this.provider,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
        baseUrl: baseUrl ?? this.baseUrl,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'provider': provider.name,
        'apiKey': apiKey,
        'model': model,
        'baseUrl': baseUrl,
      };

  factory AiSettings.fromJson(Map<String, dynamic> json) => AiSettings(
        enabled: json['enabled'] == true,
        provider: AiProvider.values.firstWhere(
          (p) => p.name == json['provider'],
          orElse: () => AiProvider.claude,
        ),
        apiKey: (json['apiKey'] ?? '') as String,
        model: (json['model'] ?? '') as String,
        baseUrl: (json['baseUrl'] ?? '') as String,
      );
}

/// A problem talking to the AI, worded for people.
class AiException implements Exception {
  AiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// What to ask the AI about a code block.
enum AiAction { explain, findBugs, improve }

extension AiActionInfo on AiAction {
  String get label => switch (this) {
        AiAction.explain => 'Explain this code',
        AiAction.findBugs => 'Find bugs',
        AiAction.improve => 'Suggest improvements',
      };

  String get command => switch (this) {
        AiAction.explain => 'explain',
        AiAction.findBugs => 'review --bugs',
        AiAction.improve => 'review --improve',
      };

  /// Title for the block that's saved into the note.
  String get savedTitle => switch (this) {
        AiAction.explain => 'Explanation',
        AiAction.findBugs => 'Possible bugs',
        AiAction.improve => 'Suggested improvements',
      };

  String prompt(String language, String code) {
    final task = switch (this) {
      AiAction.explain =>
        'Explain what this $language code does, step by step, in plain words. '
            'Start with a one-sentence summary, then a short bullet list of how it works. '
            'Mention anything surprising.',
      AiAction.findBugs =>
        'Review this $language code for bugs and risky edge cases. '
            'For each problem: what goes wrong, when, and a short fix. '
            'If you find nothing real, say so plainly. Do not invent problems.',
      AiAction.improve =>
        'Suggest the most useful improvements to this $language code '
            '(readability, performance, safety). Keep it to the top 3, each with a short example.',
    };
    return '$task\n\n```$language\n$code\n```';
  }
}

class AiService {
  AiService._();
  static final AiService instance = AiService._();

  static const _boxName = 'aiBox';
  static const _key = 'AI_SETTINGS';
  static const _system =
      'You help a developer understand code saved in their notebook app. '
      'Answer in concise Markdown: short paragraphs, bullet lists, and code blocks when useful.';

  Future<Box> _box() => Hive.isBoxOpen(_boxName)
      ? Future.value(Hive.box(_boxName))
      : Hive.openBox(_boxName);

  Future<AiSettings> load() async {
    final raw = (await _box()).get(_key);
    if (raw is! String) return const AiSettings();
    try {
      return AiSettings.fromJson(json.decode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const AiSettings();
    }
  }

  Future<void> save(AiSettings settings) async =>
      (await _box()).put(_key, json.encode(settings.toJson()));

  /// Sends [prompt] and returns the answer as Markdown.
  Future<String> ask(String prompt, {AiSettings? settings}) async {
    final s = settings ?? await load();
    if (!s.isReady) {
      throw AiException('Set up AI first in Settings > AI assistant.');
    }
    try {
      return switch (s.provider) {
        AiProvider.claude => await _claude(s, prompt),
        AiProvider.openAiCompatible => await _openAi(s, prompt),
        AiProvider.ollama => await _ollama(s, prompt),
      };
    } on AiException {
      rethrow;
    } on TimeoutException {
      throw AiException('The AI took too long to answer. Try again.');
    } catch (e) {
      throw AiException(s.provider == AiProvider.ollama
          ? "Couldn't reach Ollama at ${s.effectiveBaseUrl}. Is it running?"
          : "Couldn't reach ${s.provider.label}. Check your internet connection.");
    }
  }

  /// A tiny request to check the settings work.
  Future<void> test(AiSettings settings) async {
    await ask('Reply with the single word: ready',
        settings: settings.copyWith(enabled: true));
  }

  Future<String> _claude(AiSettings s, String prompt) async {
    final res = await http
        .post(
          Uri.parse('${s.effectiveBaseUrl}/v1/messages'),
          headers: {
            'content-type': 'application/json',
            'x-api-key': s.apiKey.trim(),
            'anthropic-version': '2023-06-01',
          },
          body: json.encode({
            'model': s.effectiveModel,
            'max_tokens': 1500,
            'system': _system,
            'messages': [
              {'role': 'user', 'content': prompt},
            ],
          }),
        )
        .timeout(const Duration(seconds: 90));
    final body = _decode(res);
    final content = body['content'];
    if (content is List) {
      final text = content
          .whereType<Map>()
          .where((c) => c['type'] == 'text')
          .map((c) => c['text'])
          .join('\n')
          .trim();
      if (text.isNotEmpty) return text;
    }
    throw AiException('The AI sent an empty answer.');
  }

  Future<String> _openAi(AiSettings s, String prompt) async {
    final res = await http
        .post(
          Uri.parse('${s.effectiveBaseUrl}/v1/chat/completions'),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer ${s.apiKey.trim()}',
          },
          body: json.encode({
            'model': s.effectiveModel,
            'messages': [
              {'role': 'system', 'content': _system},
              {'role': 'user', 'content': prompt},
            ],
          }),
        )
        .timeout(const Duration(seconds: 90));
    final body = _decode(res);
    final choices = body['choices'];
    if (choices is List && choices.isNotEmpty) {
      final text = (choices.first['message']?['content'] ?? '').toString().trim();
      if (text.isNotEmpty) return text;
    }
    throw AiException('The AI sent an empty answer.');
  }

  Future<String> _ollama(AiSettings s, String prompt) async {
    final res = await http
        .post(
          Uri.parse('${s.effectiveBaseUrl}/api/chat'),
          headers: {'content-type': 'application/json'},
          body: json.encode({
            'model': s.effectiveModel,
            'stream': false,
            'messages': [
              {'role': 'system', 'content': _system},
              {'role': 'user', 'content': prompt},
            ],
          }),
        )
        // Local models can be slow on the first request while they load.
        .timeout(const Duration(minutes: 3));
    final body = _decode(res);
    final text = (body['message']?['content'] ?? '').toString().trim();
    if (text.isNotEmpty) return text;
    throw AiException('The AI sent an empty answer.');
  }

  Map<String, dynamic> _decode(http.Response res) {
    Map<String, dynamic> body = {};
    try {
      final decoded = json.decode(utf8.decode(res.bodyBytes));
      if (decoded is Map<String, dynamic>) body = decoded;
    } catch (_) {}
    if (res.statusCode >= 200 && res.statusCode < 300) return body;

    final detail = (body['error'] is Map ? body['error']['message'] : body['error'])
        ?.toString();
    switch (res.statusCode) {
      case 401:
      case 403:
        throw AiException('The API key was refused. Check it in Settings > AI assistant.');
      case 404:
        throw AiException(
            'Model or address not found. Check the model name${detail == null ? '' : ': $detail'}');
      case 429:
        throw AiException('Too many requests, or the account is out of credit. Try again later.');
      default:
        throw AiException('The AI service said: ${detail ?? 'error ${res.statusCode}'}');
    }
  }
}
