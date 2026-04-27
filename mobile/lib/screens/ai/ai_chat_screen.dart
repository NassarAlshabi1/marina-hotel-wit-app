import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../services/gemini_service.dart';
import '../../services/remote_config_service.dart';

/// شاشة المساعد الذكي - Gemini AI
class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen>
    with SingleTickerProviderStateMixin {
  final List<ChatMessage> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  String? _lastUserMessage;

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
      text: 'مرحباً! أنا المساعد الذكي لفندق Marina\n\n'
          'يمكنني مساعدتك في:\n'
          '- عرض معلومات الغرف والحجوزات\n'
          '- تغيير أسعار الغرف وحالاتها\n'
          '- تسجيل دفعات ومصروفات\n'
          '- إنشاء حجوزات جديدة\n'
          '- إنهاء حجوزات وتسجيل خروج\n'
          '- تسوية الديون\n'
          '- تحديث بيانات الضيوف\n'
          '- ملخص الإيرادات والمصروفات\n\n'
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
    _lastUserMessage = text;

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
            text: 'عذراً، حدث خطأ أثناء الاتصال. تأكد من اتصالك بالإنترنت.',
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

    // تسجيل في سجل التدقيق
    GeminiService.instance.logToAudit(
      userMessage: _lastUserMessage ?? '',
      aiResponse: message.text,
      command: message.pendingCommand,
      executionResult: result,
      wasConfirmed: true,
    );

    if (mounted) {
      setState(() {
        final idx = _messages.indexOf(message);
        if (idx >= 0) {
          _messages[idx] = ChatMessage(
            id: message.id,
            text: message.text,
            isUser: false,
            timestamp: message.timestamp,
            isExecuted: true,
            executionResult: result,
          );
        }
      });
    }
  }

  Future<void> _cancelCommand(ChatMessage message) async {
    // تسجيل في سجل التدقيق — تم الإلغاء
    GeminiService.instance.logToAudit(
      userMessage: _lastUserMessage ?? '',
      aiResponse: message.text,
      command: message.pendingCommand,
      executionResult: 'تم الإلغاء بواسطة المستخدم',
      wasConfirmed: false,
    );

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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.key, color: Colors.amber),
            SizedBox(width: 8),
            Text('مفتاح Gemini API'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'أدخل مفتاح API المجاني من aistudio.google.com',
              style: TextStyle(fontSize: 13, color: Colors.grey),
              textDirection: TextDirection.rtl,
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'النموذج المستخدم: Gemini 2.0 Flash (مجاني)\nالحد: 15 طلب/دقيقة',
                style: TextStyle(fontSize: 11, color: Colors.blue),
                textDirection: TextDirection.rtl,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: keyController,
              decoration: const InputDecoration(
                labelText: 'API Key',
                hintText: 'AIza...',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.vpn_key),
              ),
              obscureText: true,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.left,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton.icon(
            onPressed: () async {
              final key = keyController.text.trim();
              if (key.isNotEmpty) {
                await RemoteConfigService.instance.setGeminiApiKey(key);
                GeminiService.instance.reset();
                await GeminiService.instance.initialize();
                if (mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('تم حفظ المفتاح وتهيئة Gemini'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  setState(() {});
                }
              }
            },
            icon: const Icon(Icons.check, size: 18),
            label: const Text('حفظ وتهيئة'),
          ),
        ],
      ),
    );
  }

  void _showAuditLog() {
    final log = GeminiService.instance.auditLog;
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.history, color: Colors.amber),
              SizedBox(width: 8),
              Text('سجل عمليات AI'),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: MediaQuery.of(context).size.height * 0.6,
            child: log.isEmpty
                ? const Center(
                    child: Text(
                      'لا توجد عمليات مسجلة بعد',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: log.length,
                    itemBuilder: (context, index) {
                      final entry = log[log.length - 1 - index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: entry.wasConfirmed
                                          ? Colors.green.withOpacity(0.15)
                                          : Colors.orange.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      entry.wasConfirmed ? 'تم' : 'ألغي',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: entry.wasConfirmed
                                            ? Colors.green
                                            : Colors.orange,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (entry.commandType != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color:
                                            Colors.blue.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        entry.commandType!
                                            .replaceAll('Ai', '')
                                            .replaceAll('Command', ''),
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Colors.blue,
                                        ),
                                      ),
                                    ),
                                  const Spacer(),
                                  Text(
                                    DateFormat('HH:mm').format(entry.timestamp),
                                    style: const TextStyle(
                                        fontSize: 10, color: Colors.grey),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                entry.userMessage,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                entry.executionResult,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: entry.executionResult.startsWith('✅')
                                      ? Colors.green
                                      : Colors.red,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            if (log.isNotEmpty)
              TextButton(
                onPressed: () {
                  GeminiService.instance.clearAuditLog();
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم مسح السجل')),
                  );
                },
                child: const Text('مسح السجل',
                    style: TextStyle(color: Colors.red)),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      ),
    );
  }

  void _clearChat() {
    setState(() {
      _messages.clear();
      GeminiService.instance.clearHistory();
      _addWelcomeMessage();
    });
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
          // سجل التدقيق
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'سجل العمليات',
            onPressed: _showAuditLog,
          ),
          // إعداد API Key
          IconButton(
            icon: const Icon(Icons.key),
            tooltip: 'إعداد API Key',
            onPressed: _showApiKeyDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          // شريط تحذير إذا لم يكن متاحاً
          if (!isAvailable)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                border: Border(
                  bottom: BorderSide(color: Colors.orange.shade200),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, color: Colors.orange.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'المساعد الذكي غير متاح — يحتاج مفتاح API مجاني من Google',
                      style: TextStyle(
                        color: Colors.orange.shade800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _showApiKeyDialog,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      backgroundColor: Colors.orange.shade100,
                    ),
                    child: Text(
                      'إعداد',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.orange.shade800,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // قائمة الرسائل
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length + (_isLoading ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= _messages.length) {
                        return _buildLoadingBubble();
                      }
                      return _buildMessageBubble(_messages[index]);
                    },
                  ),
          ),

          // اقتراحات سريعة (تظهر فقط في البداية)
          if (_messages.length <= 1 && !isAvailable)
            _buildQuickSuggestions(),

          // حقل الإدخال
          _buildInputField(theme),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.smart_toy_outlined,
              size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'ابدأ محادثة مع المساعد الذكي',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    final isUser = message.isUser;
    final theme = Theme.of(context);

    return Align(
      alignment: isUser ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? theme.colorScheme.primary.withOpacity(0.1)
              : theme.cardColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: isUser ? const Radius.circular(4) : Radius.zero,
            bottomRight: isUser ? Radius.zero : const Radius.circular(4),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // رأس الرسالة (AI فقط)
            if (!isUser)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.smart_toy,
                        size: 14, color: Colors.amber.shade700),
                    const SizedBox(width: 4),
                    Text(
                      'Marina AI',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.amber.shade700,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      DateFormat('HH:mm').format(message.timestamp),
                      style: TextStyle(
                          fontSize: 10, color: Colors.grey.shade400),
                    ),
                  ],
                ),
              ),

            // محتوى الرسالة
            Text(
              message.text,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: theme.textTheme.bodyMedium?.color,
              ),
            ),

            // نتيجة التنفيذ
            if (message.isExecuted && message.executionResult != null) ...[
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: message.executionResult!.startsWith('✅')
                      ? Colors.green.withOpacity(0.1)
                      : Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: message.executionResult!.startsWith('✅')
                        ? Colors.green.withOpacity(0.3)
                        : Colors.red.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      message.executionResult!.startsWith('✅')
                          ? Icons.check_circle
                          : Icons.error,
                      size: 14,
                      color: message.executionResult!.startsWith('✅')
                          ? Colors.green
                          : Colors.red,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        message.executionResult!,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: message.executionResult!.startsWith('✅')
                              ? Colors.green.shade800
                              : Colors.red.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // أزرار التأكيد
            if (message.pendingCommand != null) ...[
              const SizedBox(height: 10),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => _confirmCommand(message),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('تأكيد التنفيذ',
                        style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => _cancelCommand(message),
                    icon: const Icon(Icons.close, size: 16),
                    label:
                        const Text('إلغاء', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
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
        margin: const EdgeInsets.only(bottom: 10),
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
      ('📊', 'تقرير اليوم', 'أعطني تقرير اليوم'),
      ('🏠', 'الغرف الشاغرة', 'ما هي الغرف المتاحة حالياً؟'),
      ('📈', 'زيادة أسعار', 'زِد جميع الأسعار 10%'),
      ('📉', 'تخفيض سعر', 'خفّض سعر الغرفة 101 إلى 40000'),
      ('💳', 'تسجيل دفعة', 'سجّل دفعة 50000 للغرفة 101'),
      ('📋', 'تقرير الديون', 'أعطني تقرير الديون'),
      ('📊', 'نسبة الإشغال', 'كم نسبة الإشغال حالياً؟'),
      ('🏨', 'أسعار الغرف', 'أعطني تقرير أسعار الغرف'),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: suggestions.map((s) {
          return ActionChip(
            avatar: Text(s.$1, style: const TextStyle(fontSize: 14)),
            label: Text(
              s.$2,
              style: const TextStyle(fontSize: 11),
            ),
            onPressed: () {
              _controller.text = s.$3;
              _sendMessage();
            },
          );
        }).toList(),
      ),
    );
  }

  Widget _buildInputField(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: Row(
        children: [
          // زر مسح المحادثة
          if (_messages.length > 2)
            IconButton(
              onPressed: _clearChat,
              icon: Icon(Icons.delete_outline,
                  size: 20, color: Colors.grey.shade500),
              tooltip: 'مسح المحادثة',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),

          Expanded(
            child: TextField(
              controller: _controller,
              decoration: const InputDecoration(
                hintText: 'اكتب سؤالك أو أمرك هنا...',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 8),
                isDense: true,
              ),
              onSubmitted: (_) => _sendMessage(),
              minLines: 1,
              maxLines: 3,
            ),
          ),
          const SizedBox(width: 4),
          IconButton.filled(
            onPressed: _isLoading ? null : _sendMessage,
            icon: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.send, size: 18),
            style: IconButton.styleFrom(
              padding: const EdgeInsets.all(10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
