import 'package:flutter/material.dart';

import '../../services/gemini_service.dart';
import '../../services/remote_config_service.dart';

/// شاشة المساعد الذكي - Gemini AI
class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initGemini();
    _addWelcomeMessage();
  }

  Future<void> _initGemini() async {
    await GeminiService.instance.initialize();
    if (mounted) setState(() {});
  }

  void _addWelcomeMessage() {
    _messages.add(ChatMessage(
      id: 'welcome',
      text: 'مرحباً! أنا المساعد الذكي لفندق Marina 🏨\n\n'
          'يمكنني مساعدتك في:\n'
          '📊 عرض معلومات الغرف والحجوزات\n'
          '💰 تغيير أسعار الغرف\n'
          '📋 تسجيل دفعات ومصروفات\n'
          '🔄 إنهاء حجوزات\n'
          '🏠 تغيير حالات الغرف\n\n'
          'اكتب طلبك وسأساعدك!',
      isUser: false,
    ));
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isLoading) return;

    _controller.clear();
    setState(() {
      _messages.add(ChatMessage(
        id: 'user_${DateTime.now().millisecondsSinceEpoch}',
        text: text,
        isUser: true,
      ));
      _isLoading = true;
    });
    _scrollToBottom();

    try {
      final response = await GeminiService.instance.chat(text);

      if (mounted) {
        setState(() {
          _messages.add(ChatMessage(
            id: 'ai_${DateTime.now().millisecondsSinceEpoch}',
            text: response.text,
            isUser: false,
            pendingCommand:
                response.requiresConfirmation ? response.command : null,
          ));
          _isLoading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add(ChatMessage(
            id: 'error_${DateTime.now().millisecondsSinceEpoch}',
            text: 'عذراً، حدث خطأ: $e',
            isUser: false,
          ));
          _isLoading = false;
        });
        _scrollToBottom();
      }
    }
  }

  Future<void> _confirmCommand(ChatMessage message) async {
    if (message.pendingCommand == null) return;

    setState(() {
      final idx = _messages.indexOf(message);
      if (idx >= 0) {
        _messages[idx] = message.copyWith(
          text: '${message.text}\n⏳ جاري التنفيذ...',
          pendingCommand: null,
        );
      }
    });

    final result =
        await GeminiService.instance.executeCommand(message.pendingCommand!);

    if (mounted) {
      setState(() {
        final idx = _messages.indexOf(message);
        if (idx >= 0) {
          _messages[idx] = ChatMessage(
            id: message.id,
            text: '${message.text}\n\n$result',
            isUser: false,
            timestamp: message.timestamp,
          );
        }
      });
    }
  }

  Future<void> _cancelCommand(ChatMessage message) async {
    if (mounted) {
      setState(() {
        final idx = _messages.indexOf(message);
        if (idx >= 0) {
          _messages[idx] = message.copyWith(
            text: '${message.text}\n❌ تم الإلغاء',
            pendingCommand: null,
          );
        }
      });
    }
  }

  void _showApiKeyDialog() async {
    final key = await RemoteConfigService.instance.geminiApiKey;
    final keyController = TextEditingController(text: key);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('مفتاح Gemini API'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'أدخل مفتاح API من aistudio.google.com',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: keyController,
              decoration: const InputDecoration(
                labelText: 'API Key',
                hintText: 'AIza...',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.key),
              ),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () async {
              final key = keyController.text.trim();
              if (key.isNotEmpty) {
                await RemoteConfigService.instance.setGeminiApiKey(key);
                GeminiService.instance.reset();
                await GeminiService.instance.initialize();
                if (mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('✅ تم حفظ المفتاح وتهيئة Gemini')),
                  );
                  setState(() {});
                }
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAvailable = GeminiService.instance.isAvailable;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isAvailable ? Icons.smart_toy : Icons.smart_toy_outlined,
              color: isAvailable ? Colors.amber : Colors.grey,
            ),
            const SizedBox(width: 8),
            const Text('المساعد الذكي'),
            if (isAvailable) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'متصّل',
                  style: TextStyle(color: Colors.green, fontSize: 11),
                ),
              ),
            ],
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.key),
            tooltip: 'إعداد API Key',
            onPressed: _showApiKeyDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          if (!isAvailable)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Colors.orange.withOpacity(0.1),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber, color: Colors.orange, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'المساعد الذكي غير متاح. اضغط على 🔑 لإدخال مفتاح API.',
                      style:
                          TextStyle(color: Colors.orange.shade800, fontSize: 13),
                    ),
                  ),
                  TextButton(
                    onPressed: _showApiKeyDialog,
                    child: const Text('إعداد', style: TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length + (_isLoading ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= _messages.length) {
                  return _buildLoadingBubble();
                }
                return _buildMessageBubble(_messages[index]);
              },
            ),
          ),
          if (_messages.length <= 1) _buildQuickSuggestions(),
          _buildInputField(theme),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    final isUser = message.isUser;

    return Align(
      alignment: isUser ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: isUser ? const Radius.circular(16) : Radius.zero,
            bottomRight: isUser ? Radius.zero : const Radius.circular(16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUser)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.smart_toy, size: 14, color: Colors.amber.shade700),
                    const SizedBox(width: 4),
                    Text(
                      'Marina AI',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.amber.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            Text(
              message.text,
              style: TextStyle(
                fontSize: 14,
                color: isUser
                    ? Theme.of(context).textTheme.bodyMedium?.color
                    : Theme.of(context).textTheme.bodyMedium?.color,
                height: 1.5,
              ),
              textDirection: TextDirection.rtl,
            ),
            if (message.pendingCommand != null) ...[
              const SizedBox(height: 10),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => _confirmCommand(message),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('تأكيد', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => _cancelCommand(message),
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('إلغاء', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingBubble() {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.amber.shade600,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'يفكر...',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickSuggestions() {
    final suggestions = [
      ('📊 ملخص اليوم', 'أعطني ملخص حالة الفندق اليوم'),
      ('🏠 الغرف المتاحة', 'ما هي الغرف المتاحة حالياً؟'),
      ('💰 تغيير سعر', 'غيّر سعر الغرفة 101 إلى 50000'),
      ('📋 إضافة مصروف', 'أضف مصروف صيانة 20000'),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: suggestions.map((s) {
          return ActionChip(
            avatar: Text(s.$1),
            label: Text(
              s.$2,
              style: const TextStyle(fontSize: 12),
            ),
            onPressed: () {
              _controller.text = s.$2;
              _sendMessage();
            },
          );
        }).toList(),
      ),
    );
  }

  Widget _buildInputField(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              decoration: const InputDecoration(
                hintText: 'اكتب سؤالك أو أمرك هنا...',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 8),
              ),
              textDirection: TextDirection.rtl,
              onSubmitted: (_) => _sendMessage(),
              minLines: 1,
              maxLines: 3,
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: _isLoading ? null : _sendMessage,
            icon: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.send, size: 20),
          ),
        ],
      ),
    );
  }
}
