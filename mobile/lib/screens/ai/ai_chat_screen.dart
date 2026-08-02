import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../services/gemini_service.dart';
import '../../utils/performance_monitor.dart';

/// مزود AI النشط
enum AiProvider {
  gemini;

  String get displayName {
    switch (this) {
      case AiProvider.gemini:
        return 'Gemini AI';
    }
  }

  String get modelName {
    switch (this) {
      case AiProvider.gemini:
        return 'Gemini 2.5 Flash';
    }
  }
}

/// رسالة محادثة
class ChatMessage {
  ChatMessage({
    required this.id,
    required this.text,
    this.isUser = false,
    this.pendingCommand,
    this.isExecuted = false,
    this.executionResult,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final String id;
  String text;
  final bool isUser;
  final AiCommand? pendingCommand;
  final bool isExecuted;
  final String? executionResult;
  final DateTime timestamp;

  ChatMessage copyWith({String? text, bool? isExecuted, String? executionResult}) {
    return ChatMessage(
      id: id,
      text: text ?? this.text,
      isUser: isUser,
      pendingCommand: pendingCommand,
      isExecuted: isExecuted ?? this.isExecuted,
      executionResult: executionResult ?? this.executionResult,
      timestamp: timestamp,
    );
  }
}

/// شاشة المساعد الذكي — Gemini AI
class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> with SingleTickerProviderStateMixin {
  final List<ChatMessage> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  String? _lastUserMessage;
  String _loadingText = 'يفكر...';

  /// مزود AI النشط
  AiProvider _activeProvider = AiProvider.gemini;

  /// هل يتوفر Gemini؟
  bool get _isGeminiAvailable => GeminiService.instance.isAvailable;

  /// هل مزود متاح؟
  bool get _isAnyAvailable => _isGeminiAvailable;

  @override
  void initState() {
    super.initState();
    _initializeProviders();
    _addWelcomeMessage();
  }

  Future<void> _initializeProviders() async {
    // تهيئة Gemini
    await GeminiService.instance.initialize();

    _activeProvider = AiProvider.gemini;

    if (mounted) setState(() {});
  }

  /// إعادة تهيئة Gemini
  Future<void> _retryInit() async {
    setState(() => _isLoading = true);
    await GeminiService.instance.initialize(forceRetry: true);
    if (mounted) setState(() => _isLoading = false);
  }

  void _addWelcomeMessage() {
    _messages.add(
      ChatMessage(
        id: 'welcome',
        text:
            'مرحباً! أنا المساعد الذكي لفندق Marina\n\n'
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
      ),
    );
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
      _messages.add(ChatMessage(id: 'user_${DateTime.now().millisecondsSinceEpoch}', text: text, isUser: true));
      _isLoading = true;
      _loadingText = 'يفكر...';
    });
    _scrollToBottom();

    try {
      final GeminiResponse response;

      if (_isGeminiAvailable) {
        response = await GeminiService.instance.chat(text);
      } else {
        response = const GeminiResponse(text: 'Gemini AI غير متاح. تأكد من اتصالك بالإنترنت ومفتاح API.');
      }

      if (mounted) {
        setState(() {
          _messages.add(
            ChatMessage(
              id: 'ai_${DateTime.now().millisecondsSinceEpoch}',
              text: response.text,
              pendingCommand: response.requiresConfirmation ? response.command : null,
            ),
          );
          _isLoading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('❌ Chat Error: $e');
      if (mounted) {
        String errorMsg = 'عذراً، حدث خطأ أثناء الاتصال.';
        if (e.toString().contains('API_KEY') || e.toString().contains('401')) {
          errorMsg = 'خطأ في مفتاح API.';
        } else if (e.toString().contains('QUOTA') || e.toString().contains('429')) {
          errorMsg = 'تم تجاوز حد الطلبات المسموح به.';
        }

        setState(() {
          _messages.add(
            ChatMessage(
              id: 'error_${DateTime.now().millisecondsSinceEpoch}',
              text: '$errorMsg\nتأكد من اتصالك بالإنترنت.',
            ),
          );
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
        _messages[idx] = message.copyWith(text: '${message.text}\n⏳ جاري التنفيذ...');
      }
    });

    final result = await GeminiService.instance.executeCommand(message.pendingCommand!);

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
            timestamp: message.timestamp,
            isExecuted: true,
            executionResult: result,
          );
        }
      });
    }
  }

  Future<void> _cancelCommand(ChatMessage message) async {
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
          _messages[idx] = message.copyWith(text: '${message.text}\n❌ تم الإلغاء');
        }
      });
    }
  }

  void _showAuditLog() {
    final log = GeminiService.instance.auditLog;
    showDialog<void>(
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
                    child: Text('لا توجد عمليات مسجلة بعد', style: TextStyle(color: Colors.grey)),
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
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: entry.wasConfirmed
                                          ? Colors.green.withValues(alpha: 0.15)
                                          : Colors.orange.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      entry.wasConfirmed ? 'تم' : 'ألغي',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: entry.wasConfirmed ? Colors.green : Colors.orange,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (entry.commandType != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        entry.commandType!.replaceAll('Ai', '').replaceAll('Command', ''),
                                        style: const TextStyle(fontSize: 10, color: Colors.blue),
                                      ),
                                    ),
                                  const Spacer(),
                                  Text(
                                    DateFormat('HH:mm').format(entry.timestamp),
                                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                entry.userMessage,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                entry.executionResult,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: entry.executionResult.startsWith('✅') ? Colors.green : Colors.red,
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
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم مسح السجل')));
                },
                child: const Text('مسح السجل', style: TextStyle(color: Colors.red)),
              ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
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
    final theme = Theme.of(context);

    return PerformanceInspector(
      name: 'AiChatScreen',
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _isAnyAvailable ? Icons.smart_toy : Icons.smart_toy_outlined,
                color: _isAnyAvailable ? Colors.amber : Colors.grey,
              ),
              const SizedBox(width: 8),
              const Text('المساعد الذكي'),
              if (_isAnyAvailable) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(_activeProvider.displayName, style: const TextStyle(color: Colors.green, fontSize: 11)),
                ),
              ],
            ],
          ),
          actions: [
            // سجل التدقيق
            IconButton(icon: const Icon(Icons.history), tooltip: 'سجل العمليات', onPressed: _showAuditLog),
          ],
        ),
        body: Column(
          children: [
            // شريط تحذير إذا لم يكن متاحاً
            if (!_isAnyAvailable)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  border: Border(bottom: BorderSide(color: Colors.orange.shade200)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber, color: Colors.orange.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'المساعد الذكي غير متاح',
                            style: TextStyle(color: Colors.orange.shade800, fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                          if (GeminiService.instance.initError != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Gemini: ${GeminiService.instance.initError}',
                              style: TextStyle(color: Colors.orange.shade700, fontSize: 11),
                            ),
                          ],

                          const SizedBox(height: 6),
                          SizedBox(
                            height: 28,
                            child: ElevatedButton.icon(
                              onPressed: _retryInit,
                              icon: const Icon(Icons.refresh, size: 14),
                              label: const Text('إعادة المحاولة', style: TextStyle(fontSize: 11)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange.shade700,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                        ],
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
                          return RepaintBoundary(child: _buildLoadingBubble());
                        }
                        return _buildMessageBubble(_messages[index]);
                      },
                    ),
            ),

            // اقتراحات سريعة
            if (_messages.length <= 1 && !_isAnyAvailable) _buildQuickSuggestions(),

            // حقل الإدخال
            _buildInputField(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.smart_toy_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('ابدأ محادثة مع المساعد الذكي', style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
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
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        decoration: BoxDecoration(
          color: isUser ? theme.colorScheme.primary.withValues(alpha: 0.1) : theme.cardColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: isUser ? const Radius.circular(4) : Radius.zero,
            bottomRight: isUser ? Radius.zero : const Radius.circular(4),
          ),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4, offset: const Offset(0, 2)),
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
                    Icon(Icons.smart_toy, size: 14, color: Colors.amber.shade700),
                    const SizedBox(width: 4),
                    Text(
                      _activeProvider.displayName,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber.shade700),
                    ),
                    const Spacer(),
                    Text(
                      DateFormat('HH:mm').format(message.timestamp),
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
                    ),
                  ],
                ),
              ),

            // محتوى الرسالة
            Text(message.text, style: TextStyle(fontSize: 14, height: 1.5, color: theme.textTheme.bodyMedium?.color)),

            // نتيجة التنفيذ
            if (message.isExecuted && message.executionResult != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: message.executionResult!.startsWith('✅')
                      ? Colors.green.withValues(alpha: 0.1)
                      : Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: message.executionResult!.startsWith('✅')
                        ? Colors.green.withValues(alpha: 0.3)
                        : Colors.red.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      message.executionResult!.startsWith('✅') ? Icons.check_circle : Icons.error,
                      size: 14,
                      color: message.executionResult!.startsWith('✅') ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        message.executionResult!,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: message.executionResult!.startsWith('✅') ? Colors.green.shade800 : Colors.red.shade800,
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
                    label: const Text('تأكيد التنفيذ', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => _cancelCommand(message),
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('إلغاء', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber.shade600),
            ),
            const SizedBox(width: 8),
            Text(_loadingText, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
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
            label: Text(s.$2, style: const TextStyle(fontSize: 11)),
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
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(top: BorderSide(color: theme.dividerColor, width: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // زر مسح المحادثة
          if (_messages.length > 2)
            SizedBox(
              width: 32,
              height: 32,
              child: IconButton(
                onPressed: _clearChat,
                icon: Icon(Icons.delete_outline, size: 18, color: Colors.grey.shade500),
                tooltip: 'مسح المحادثة',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ),

          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              child: TextField(
                controller: _controller,
                style: const TextStyle(fontSize: 16, height: 1.4),
                decoration: InputDecoration(
                  hintText: 'اكتب هنا...',
                  hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.5), width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  isDense: true,
                  filled: true,
                  fillColor: theme.scaffoldBackgroundColor,
                ),
                onSubmitted: (_) => _sendMessage(),
                minLines: 1,
                maxLines: 4,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 42,
            height: 42,
            child: IconButton.filled(
              onPressed: _isLoading ? null : _sendMessage,
              icon: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send, size: 20),
              style: IconButton.styleFrom(
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
