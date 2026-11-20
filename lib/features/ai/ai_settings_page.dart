import 'package:flutter/material.dart';

import '../../constants/themes.dart';
import 'ai_service.dart';

/// Settings > AI assistant: pick a provider, add a key, test it.
class AiSettingsPage extends StatefulWidget {
  const AiSettingsPage({super.key});

  @override
  State<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends State<AiSettingsPage> {
  AiSettings _settings = const AiSettings();
  bool _loading = true;
  bool _testing = false;
  bool _showKey = false;
  String? _testResult;
  bool _testOk = false;

  List<LocalModel>? _localModels;
  bool _scanning = false;

  final _keyController = TextEditingController();
  final _modelController = TextEditingController();
  final _urlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    AiService.instance.load().then((s) {
      if (!mounted) return;
      setState(() {
        _settings = s;
        _keyController.text = s.apiKey;
        _modelController.text = s.model;
        _urlController.text = s.baseUrl;
        _loading = false;
      });
      _scan();
    });
  }

  /// Finds Ollama and LM Studio models on this computer.
  Future<void> _scan() async {
    setState(() => _scanning = true);
    final found = await AiService.instance.discoverLocalModels(
      extraUrl: _settings.provider == AiProvider.ollama ? _urlController.text : null,
    );
    if (!mounted) return;
    setState(() {
      _localModels = found;
      _scanning = false;
    });
  }

  Future<void> _useLocal(LocalModel m) async {
    _modelController.text = m.name;
    _urlController.text =
        m.baseUrl == m.provider.defaultBaseUrl ? '' : m.baseUrl;
    await _save(_current.copyWith(
      provider: m.provider,
      model: m.name,
      baseUrl: _urlController.text,
      enabled: true,
    ));
    setState(() {
      _testOk = true;
      _testResult = 'Using ${m.name} from ${m.runner}. Nothing leaves this computer.';
    });
  }

  @override
  void dispose() {
    _keyController.dispose();
    _modelController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  AiSettings get _current => _settings.copyWith(
        apiKey: _keyController.text.trim(),
        model: _modelController.text.trim(),
        baseUrl: _urlController.text.trim(),
      );

  Future<void> _save([AiSettings? s]) async {
    final next = s ?? _current;
    setState(() => _settings = next);
    await AiService.instance.save(next);
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      await AiService.instance.test(_current);
      _testOk = true;
      _testResult = 'Connected. ${_current.provider.label} is ready.';
      await _save(_current.copyWith(enabled: true));
    } on AiException catch (e) {
      _testOk = false;
      _testResult = e.message;
    }
    if (mounted) setState(() => _testing = false);
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final provider = _settings.provider;

    return Scaffold(
      appBar: AppBar(title: const Text('AI assistant')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Use AI on code blocks'),
                      subtitle: const Text(
                          'Adds ✨ Explain, Find bugs and Improve to every code block.'),
                      value: _settings.enabled,
                      onChanged: (v) => _save(_current.copyWith(enabled: v)),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: color.surfaceContainer,
                        borderRadius: BorderRadius.circular(AppBrand.radiusSmall),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.shield_outlined, size: 18, color: tokens.subtle),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'CodeNote stays local-only. Only the code block you ask about is sent, '
                              'only when you tap an AI button, and only to the service you pick here. '
                              'With Ollama, nothing leaves your computer. Your key is stored on this device only.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Text('// local models',
                            style: monoStyle(context,
                                size: 12, weight: FontWeight.w700, color: color.primary)),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: _scanning ? null : _scan,
                          icon: _scanning
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.radar_rounded, size: 18),
                          label: Text(_scanning ? 'Looking…' : 'Scan again'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (_localModels != null && _localModels!.isEmpty && !_scanning)
                      Text(
                        'No local models found. Install Ollama (ollama.com) or LM Studio, '
                        'download a model, then tap Scan again.',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: tokens.subtle),
                      )
                    else if (_localModels != null)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final m in _localModels!)
                            ChoiceChip(
                              avatar: Icon(Icons.memory_rounded,
                                  size: 16, color: tokens.success),
                              label: Text('${m.name} · ${m.runner}'),
                              selected: _settings.provider == m.provider &&
                                  _settings.effectiveModel == m.name,
                              onSelected: (_) => _useLocal(m),
                            ),
                        ],
                      ),
                    const SizedBox(height: 24),
                    Text('// provider',
                        style: monoStyle(context,
                            size: 12, weight: FontWeight.w700, color: color.primary)),
                    const SizedBox(height: 10),
                    SegmentedButton<AiProvider>(
                      segments: [
                        for (final p in AiProvider.values)
                          ButtonSegment(value: p, label: Text(p.label)),
                      ],
                      selected: {provider},
                      showSelectedIcon: false,
                      onSelectionChanged: (v) {
                        _testResult = null;
                        _save(_current.copyWith(provider: v.first));
                      },
                    ),
                    const SizedBox(height: 20),
                    if (provider.needsKey) ...[
                      TextField(
                        controller: _keyController,
                        obscureText: !_showKey,
                        autocorrect: false,
                        enableSuggestions: false,
                        style: monoStyle(context, size: 13),
                        decoration: InputDecoration(
                          labelText: 'API key',
                          hintText: provider == AiProvider.claude ? 'sk-ant-…' : 'sk-…',
                          suffixIcon: IconButton(
                            tooltip: _showKey ? 'Hide key' : 'Show key',
                            icon: Icon(_showKey
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined),
                            onPressed: () => setState(() => _showKey = !_showKey),
                          ),
                        ),
                        onChanged: (_) => _save(),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        provider == AiProvider.claude
                            ? 'Get a key at console.anthropic.com.'
                            : 'Works with OpenAI, OpenRouter, Groq, LM Studio and other OpenAI-style APIs.',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: tokens.subtle),
                      ),
                      const SizedBox(height: 16),
                    ] else ...[
                      Text(
                        'Install Ollama from ollama.com, then run:\n'
                        '  ollama pull ${provider.defaultModel}\n'
                        'Free, offline, and nothing leaves your computer.',
                        style: monoStyle(context, size: 12, color: tokens.subtle),
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextField(
                      controller: _modelController,
                      style: monoStyle(context, size: 13),
                      decoration: InputDecoration(
                        labelText: 'Model',
                        hintText: provider.defaultModel,
                        helperText: 'Leave empty to use ${provider.defaultModel}',
                      ),
                      onChanged: (_) => _save(),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _urlController,
                      style: monoStyle(context, size: 13),
                      keyboardType: TextInputType.url,
                      decoration: InputDecoration(
                        labelText: 'Server address',
                        hintText: provider.defaultBaseUrl,
                        helperText: 'Leave empty for ${provider.defaultBaseUrl}',
                      ),
                      onChanged: (_) => _save(),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _testing ? null : _test,
                      icon: _testing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.bolt_rounded),
                      label: Text(_testing ? 'Testing…' : 'Test connection'),
                    ),
                    if (_testResult != null) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(
                            _testOk ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                            size: 18,
                            color: _testOk ? tokens.success : color.error,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(_testResult!,
                                style: TextStyle(
                                    color: _testOk ? tokens.success : color.error)),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}
