// TODO(phase-2): remove this ignore and fix violations (discarded_futures)
// ignore_for_file: discarded_futures
// lib/screens/settings/ai_settings_screen.dart
// شاشة إعدادات المساعد الذكي — تتيح تخصيص المزود والموديل ومفتاح API

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/ai_settings_service.dart';
import '../../services/gemini_service.dart';

class AiSettingsScreen extends ConsumerStatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  ConsumerState<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends ConsumerState<AiSettingsScreen> {
  late AiSettingsService _settings;
  final _apiKeyController = TextEditingController();
  final _baseUrlController = TextEditingController();
  final _extraPromptController = TextEditingController();
  String _selectedProvider = 'gemini';
  String _selectedModel = 'gemini-2.5-flash';
  double _temperature = 0.2;
  int _maxTokens = 4096;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _settings = AiSettingsService.instance;
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    await _settings.initialize();
    setState(() {
      _selectedProvider = _settings.provider;
      _selectedModel = _settings.model;
      _apiKeyController.text = _settings.apiKey;
      _baseUrlController.text = _settings.baseUrl;
      _temperature = _settings.temperature;
      _maxTokens = _settings.maxTokens;
      _extraPromptController.text = _settings.systemPromptExtra;
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    _settings.provider = _selectedProvider;
    _settings.model = _selectedModel;
    _settings.apiKey = _apiKeyController.text.trim();
    _settings.baseUrl = _baseUrlController.text.trim();
    _settings.temperature = _temperature;
    _settings.maxTokens = _maxTokens;
    _settings.systemPromptExtra = _extraPromptController.text.trim();

    // إعادة تهيئة GeminiService بالإعدادات الجديدة
    GeminiService.instance.reset();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ تم حفظ إعدادات AI'),
        backgroundColor: Colors.green,
      ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final models = AiModelOption.getModelsForProvider(_selectedProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('إعدادات المساعد الذكي'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveSettings,
            tooltip: 'حفظ',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ═══ اختيار المزود ═══
          _buildSectionTitle('مزود الخدمة'),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'gemini',
                label: Text('Gemini'),
                icon: Icon(Icons.auto_awesome),
              ),
              ButtonSegment(
                value: 'openrouter',
                label: Text('OpenRouter'),
                icon: Icon(Icons.hub),
              ),
            ],
            selected: {_selectedProvider},
            onSelectionChanged: (value) {
              setState(() {
                _selectedProvider = value.first;
                // تحديث الموديل الافتراضي عند تغيير المزود
                final newModels = AiModelOption.getModelsForProvider(
                  _selectedProvider,
                );
                _selectedModel = newModels.first.id;
              });
            },
          ),
          const SizedBox(height: 24),

          // ═══ اختيار الموديل ═══
          _buildSectionTitle('الموديل'),
          const SizedBox(height: 8),
          ...models.map(
            (m) => RadioListTile<String>(
              title: Text(m.displayName),
              subtitle: Text(m.description),
              value: m.id,
              // ignore: deprecated_member_use
              groupValue: _selectedModel,
              // ignore: deprecated_member_use
              onChanged: (value) {
                setState(() => _selectedModel = value!);
              },
            ),
          ),

          // ═══ إعدادات OpenRouter ═══
          if (_selectedProvider == 'openrouter') ...[
            const SizedBox(height: 24),
            _buildSectionTitle('إعدادات OpenRouter'),
            const SizedBox(height: 8),
            TextField(
              controller: _apiKeyController,
              decoration: const InputDecoration(
                labelText: 'مفتاح API (OpenRouter)',
                hintText: 'sk-or-v1-xxxxx',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.key),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _baseUrlController,
              decoration: const InputDecoration(
                labelText: 'عنوان API',
                hintText: 'https://openrouter.ai/api/v1',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.link),
              ),
            ),
            const SizedBox(height: 8),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.info, color: Colors.blue),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'احصل على مفتاح API من openrouter.ai/keys\n'
                        'يدعم: Gemini, Claude, GPT-4, Llama',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          // ═══ إعدادات متقدمة ═══
          const SizedBox(height: 24),
          _buildSectionTitle('إعدادات متقدمة'),
          const SizedBox(height: 8),

          // Temperature
          Text(
            'درجة الإبداع (Temperature): ${_temperature.toStringAsFixed(1)}',
          ),
          Slider(
            value: _temperature,
            divisions: 10,
            label: _temperature.toStringAsFixed(1),
            onChanged: (v) => setState(() => _temperature = v),
          ),
          const SizedBox(height: 8),

          // Max tokens
          Text('الحد الأقصى للتوكنز: $_maxTokens'),
          Slider(
            value: _maxTokens.toDouble(),
            min: 1024,
            max: 8192,
            divisions: 14,
            label: '$_maxTokens',
            onChanged: (v) => setState(() => _maxTokens = v.round()),
          ),
          const SizedBox(height: 16),

          // System prompt extra
          TextField(
            controller: _extraPromptController,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'تعليمات إضافية للمساعد (اختياري)',
              hintText: 'مثال: ركّز على التحليل المالي، أو كن أكثر اختصاراً',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.edit_note),
            ),
          ),

          const SizedBox(height: 24),

          // ═══ أزرار ═══
          FilledButton.icon(
            onPressed: _saveSettings,
            icon: const Icon(Icons.save),
            label: const Text('حفظ الإعدادات'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              await _settings.resetToDefaults();
              await _loadSettings();
              GeminiService.instance.reset();
              if (!mounted) return;
              messenger.showSnackBar(
                const SnackBar(
                  content: Text('تم استعادة الإعدادات الافتراضية'),
                ),
              );
            },
            icon: const Icon(Icons.restore),
            label: const Text('استعادة الافتراضي'),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: Colors.deepOrange,
      ),
    );
  }
}
