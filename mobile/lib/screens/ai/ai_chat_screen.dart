// lib/screens/ai/ai_chat_screen.dart
// شاشة المحادثة مع المساعد الذكي "ماريانا"
// ✅ تصميم محسّن + نسخ المخرجات + تنسيق احترافي للأوامر

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../services/gemini_service.dart';
import '../../services/ai_settings_service.dart';
import '../../services/crashlytics_service.dart';
import '../../utils/hotel_time_engine.dart';
import '../settings/ai_settings_screen.dart';

// ═══ نموذج رسالة المحادثة ═══
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.text,
    required this.isUser,
    this.isError = false,
    this.timestamp,
    this.isCommandResult = false,
  });

  final String id;
  final String text;
  final bool isUser;
  final bool isError;
  final DateTime? timestamp;
  final bool isCommandResult;

  ChatMessage copyWith({
    String? text,
    bool? isUser,
    bool? isError,
    bool? isCommandResult,
  }) {
    return ChatMessage(
      id: id,
      text: text ?? this.text,
      isUser: isUser ?? this.isUser,
      isError: isError ?? this.isError,
      timestamp: timestamp ?? this.timestamp,
      isCommandResult: isCommandResult ?? this.isCommandResult,
    );
  }
}

// ═══ الشاشة الرئيسية ═══
class AiChatScreen extends ConsumerStatefulWidget {
  const AiChatScreen({super.key});

  @override
  ConsumerState<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends ConsumerState<AiChatScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;

  final _quickActions = [
    '📊 ملخص اليوم المالي',
    '🛏️ الغرف الشاغرة',
    '⚠️ الحجوزات المتأخرة',
    '💰 أكبر الديون',
    '📅 تقرير الأمس',
    '🔢 إحصائيات الإشغال',
  ];

  @override
  void initState() {
    super.initState();
    _initializeAI();
  }

  Future<void> _initializeAI() async {
    await GeminiService.instance.initialize();
    if (mounted) setState(() {});
  }

  Future<void> _retryInit() async {
    await GeminiService.instance.initialize(forceRetry: true);
    if (mounted) setState(() {});
  }

  bool get _isGeminiAvailable => GeminiService.instance.isAvailable;

  Future<void> _sendMessage({String? presetMessage}) async {
    final text = presetMessage ?? _inputController.text.trim();
    if (text.isEmpty || _isLoading) return;

    _inputController.clear();

    // إضافة رسالة المستخدم
    final userMsg = ChatMessage(
      id: 'user_${DateTime.now().millisecondsSinceEpoch}',
      text: text,
      isUser: true,
      timestamp: DateTime.now(),
    );
    setState(() {
      _messages.add(userMsg);
      _isLoading = true;
    });
    _scrollToBottom();

    try {
      // إرسال للمساعد الذكي
      final response = await GeminiService.instance.chat(text);

      // إضافة رد المساعد
      final aiMsg = ChatMessage(
        id: 'ai_${DateTime.now().millisecondsSinceEpoch}',
        text: response.text,
        isUser: false,
        isError:
            response.text.contains('خطأ') ||
            response.text.contains('عذراً') ||
            response.text.contains('غير متاح'),
        timestamp: DateTime.now(),
        isCommandResult: response.hasCommand,
      );
      setState(() {
        _messages.add(aiMsg);
        _isLoading = false;
      });

      // تنفيذ الأمر إذا كان موجوداً
      if (response.hasCommand && response.command != null) {
        _executeCommand(response.command!, text);
      }

      // تتبع في Crashlytics
      await CrashlyticsService.instance.setSyncStatus('ai_chat_idle');

      _scrollToBottom();
    } catch (e) {
      setState(() {
        _messages.add(
          ChatMessage(
            id: 'err_${DateTime.now().millisecondsSinceEpoch}',
            text: _friendlyError(e),
            isUser: false,
            isError: true,
            timestamp: DateTime.now(),
          ),
        );
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  Future<void> _executeCommand(AiCommand command, String userMessage) async {
    try {
      final result = await GeminiService.instance.executeCommand(
        command,
        confirmed: command is! AiQueryCommand,
      );

      if (mounted) {
        setState(() {
          _messages.add(
            ChatMessage(
              id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
              text: result,
              isUser: false,
              isCommandResult: true,
              timestamp: DateTime.now(),
            ),
          );
        });
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('Command execution error: $e');
    }
  }

  String _friendlyError(Object e) {
    final msg = e.toString();
    if (msg.contains('401') || msg.contains('API_KEY')) {
      return '🔑 خطأ في مفتاح API.\n\nالحل:\n1. افتح إعدادات AI\n2. غيّر المزود إلى OpenRouter\n3. أدخل مفتاح API صالح';
    } else if (msg.contains('429') || msg.contains('QUOTA')) {
      return '⏳ تم تجاوز حد الطلبات.\nانتظر 30 ثانية ثم حاول مجدداً.';
    } else if (msg.contains('network') || msg.contains('socket')) {
      return '📡 خطأ في الاتصال.\nتحقق من الإنترنت.';
    }
    return '❌ حدث خطأ: $e';
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

  void _copyMessage(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ تم نسخ النص'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFB46B00), Color(0xFFD9A621)],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.auto_awesome,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ماريانا',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'المساعد الذكي',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // زر الإعدادات
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'إعدادات AI',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AiSettingsScreen()),
              ).then((_) {
                // إعادة التهيئة بعد تغيير الإعدادات
                GeminiService.instance.reset();
                _initializeAI();
              });
            },
          ),
          // زر مسح المحادثة
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'محادثة جديدة',
            onPressed: () {
              setState(() {
                _messages.clear();
                GeminiService.instance.clearHistory();
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // شريط حالة الـ AI
          if (!_isGeminiAvailable)
            _buildUnavailableBar()
          else
            _buildStatusBar(theme),

          // قائمة الرسائل
          Expanded(
            child: _messages.isEmpty
                ? _buildWelcomeScreen()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    itemCount: _messages.length + (_isLoading ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= _messages.length) {
                        return _buildTypingIndicator();
                      }
                      return _buildMessageBubble(_messages[index]);
                    },
                  ),
          ),

          // اقتراحات سريعة
          if (_messages.length <= 1 && _isGeminiAvailable) _buildQuickActions(),

          // حقل الإدخال
          _buildInputField(theme),
        ],
      ),
    );
  }

  // ═══ شريط "غير متاح" ═══
  Widget _buildUnavailableBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber, color: Colors.orange.shade700, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'المساعد الذكي غير متاح',
                  style: TextStyle(
                    color: Colors.orange.shade800,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (GeminiService.instance.initError != null)
                  Text(
                    GeminiService.instance.initError!,
                    style: TextStyle(
                      color: Colors.orange.shade600,
                      fontSize: 11,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _retryInit,
            icon: const Icon(Icons.refresh, size: 14),
            label: const Text('إعادة', style: TextStyle(fontSize: 11)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══ شريط الحالة ═══
  Widget _buildStatusBar(ThemeData theme) {
    final model = AiSettingsService.instance.model;
    final provider = AiSettingsService.instance.provider == 'gemini'
        ? 'Gemini'
        : 'OpenRouter';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Colors.green,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'متصل · $provider · $model',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
            ),
          ),
          const Spacer(),
          Text(
            'اليوم الفندقي: ${HotelTimeEngine.getHotelDayKey()}',
            style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  // ═══ شاشة الترحيب ═══
  Widget _buildWelcomeScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFB46B00), Color(0xFFD9A621)],
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.auto_awesome,
              color: Colors.white,
              size: 40,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'مرحباً، أنا ماريانا',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'مساعدتك الذكية لإدارة فندق مارينا',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 24),
          // اقتراحات سريعة في شاشة الترحيب
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: _quickActions.map((action) {
              return ActionChip(
                label: Text(action),
                onPressed: () => _sendMessage(presetMessage: action),
                backgroundColor: Colors.deepOrange.shade50,
                labelStyle: TextStyle(
                  fontSize: 12,
                  color: Colors.deepOrange.shade700,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ═══ فقاعة الرسالة ═══
  Widget _buildMessageBubble(ChatMessage message) {
    final isUser = message.isUser;
    final theme = Theme.of(context);

    return Align(
      alignment: isUser ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        decoration: BoxDecoration(
          gradient: isUser
              ? const LinearGradient(
                  colors: [Color(0xFF1B3A5C), Color(0xFF2D5A8C)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isUser
              ? null
              : (message.isError ? Colors.red.shade50 : theme.cardColor),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: isUser ? const Radius.circular(4) : Radius.zero,
            bottomRight: isUser ? Radius.zero : const Radius.circular(4),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
          border: !isUser && message.isError
              ? Border.all(color: Colors.red.shade200)
              : !isUser && message.isCommandResult
              ? Border.all(color: Colors.green.shade200)
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // رأس الرسالة (AI فقط)
            if (!isUser)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFB46B00), Color(0xFFD9A621)],
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(
                        Icons.auto_awesome,
                        color: Colors.white,
                        size: 12,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      message.isError
                          ? '⚠️ خطأ'
                          : (message.isCommandResult
                                ? '✅ تم التنفيذ'
                                : 'ماريانا'),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: message.isError
                            ? Colors.red.shade700
                            : Colors.deepOrange,
                      ),
                    ),
                    const Spacer(),
                    // زر النسخ
                    IconButton(
                      icon: const Icon(Icons.copy_outlined, size: 14),
                      tooltip: 'نسخ',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      onPressed: () => _copyMessage(message.text),
                    ),
                  ],
                ),
              ),
            // محتوى الرسالة
            Padding(
              padding: isUser
                  ? const EdgeInsets.symmetric(horizontal: 14, vertical: 10)
                  : const EdgeInsets.fromLTRB(14, 6, 14, 10),
              child: _buildFormattedText(message.text, isUser),
            ),
            // تذييل الوقت (AI فقط)
            if (!isUser && message.timestamp != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                child: Row(
                  children: [
                    Text(
                      DateFormat('HH:mm').format(message.timestamp!),
                      style: TextStyle(
                        fontSize: 9,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ═══ تنسيق النص (يدعم أسطر متعددة وقوائم) ═══
  Widget _buildFormattedText(String text, bool isUser) {
    final color = isUser
        ? Colors.white
        : (text.contains('خطأ') ? Colors.red.shade800 : Colors.black87);

    // تقسيم النص لأسطر
    final lines = text.split('\n');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines.map((line) {
        // تنسيق العناوين (تبدأ بـ ═══ أو ─── أو ▸ أو ●)
        if (line.contains('═══') || line.contains('───')) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              line,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isUser ? Colors.white70 : Colors.deepOrange,
              ),
            ),
          );
        }

        // تنسيق القوائم (تبدأ بـ • أو - أو رقم)
        if (line.trimLeft().startsWith('•') ||
            line.trimLeft().startsWith('-') ||
            line.trimLeft().startsWith('▸') ||
            RegExp(r'^\d+\.').hasMatch(line.trimLeft())) {
          return Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Text(
              line,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: color,
              ),
            ),
          );
        }

        // نص عادي
        return Text(
          line,
          style: TextStyle(
            fontSize: 13,
            height: 1.4,
            color: color,
          ),
        );
      }).toList(),
    );
  }

  // ═══ مؤشر الكتابة ═══
  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.zero,
            bottomRight: Radius.circular(4),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('ماريانا يكتب'),
            const SizedBox(width: 8),
            _buildDot(0),
            _buildDot(1),
            _buildDot(2),
          ],
        ),
      ),
    );
  }

  Widget _buildDot(int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.3, end: 1.0),
      duration: Duration(milliseconds: 600 + index * 200),
      builder: (context, value, child) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: Colors.deepOrange.withValues(alpha: value),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }

  // ═══ الاقتراحات السريعة ═══
  Widget _buildQuickActions() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _quickActions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          return ActionChip(
            label: Text(
              _quickActions[index],
              style: const TextStyle(fontSize: 12),
            ),
            onPressed: () => _sendMessage(presetMessage: _quickActions[index]),
            backgroundColor: Colors.deepOrange.shade50,
            labelStyle: TextStyle(color: Colors.deepOrange.shade700),
            side: BorderSide(color: Colors.deepOrange.shade100),
          );
        },
      ),
    );
  }

  // ═══ حقل الإدخال ═══
  Widget _buildInputField(ThemeData theme) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          border: Border(
            top: BorderSide(color: theme.dividerColor, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: theme.dividerColor),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _inputController,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                        enabled: _isGeminiAvailable && !_isLoading,
                        maxLines: null,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'اكتب رسالتك...',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.mic_outlined, size: 20),
                      onPressed: () {
                        // TODO: voice input
                      },
                      tooltip: 'إدخال صوتي',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFB46B00), Color(0xFFD9A621)],
                ),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.send, color: Colors.white, size: 20),
                onPressed: _isLoading || !_isGeminiAvailable
                    ? null
                    : () => _sendMessage(),
                tooltip: 'إرسال',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
