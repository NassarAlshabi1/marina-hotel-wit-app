import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/cloudflare_ai_service.dart';

class _Message {
  const _Message({required this.text, required this.user, this.plan, this.executed = false});
  final String text;
  final bool user;
  final Map<String, dynamic>? plan;
  final bool executed;

  _Message copyWith({String? text, Map<String, dynamic>? plan, bool? executed}) => _Message(
        text: text ?? this.text,
        user: user,
        plan: plan ?? this.plan,
        executed: executed ?? this.executed,
      );
}

/// مساعد الفندق عبر Cloudflare Workers AI.
/// الاستعلامات تقرأ من D1، والكتابات لا تنفذ إلا بعد تأكيد المستخدم.
class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _messages = <_Message>[];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _messages.add(const _Message(
      user: false,
      text: 'مرحباً، أنا مساعد Marina عبر Cloudflare Workers AI.\n\n'
          'جرّب:\n'
          '• أضف مصروف ديزل 40000 يومياً من 2026-09-01 إلى 2026-09-19\n'
          '• كم سُحب من راتب محمد؟\n'
          '• ما هي الغرف الشاغرة؟\n'
          '• من النزلاء الموجودون حالياً؟\n'
          '• ابحث عن النزيل أحمد أو الغرفة 101\n'
          '• أعطني إجمالي المصروفات بين 2026-09-01 و2026-09-19\n\n'
          'سأعرض أي عملية إضافة للمراجعة قبل تنفيذها.',
    ));
  }

  Future<void> _send() async {
    final prompt = _controller.text.trim();
    if (prompt.isEmpty || _loading) return;
    _controller.clear();
    setState(() {
      _messages.add(_Message(text: prompt, user: true));
      _loading = true;
    });
    _scrollToEnd();
    try {
      final result = await CloudflareAiService.instance.ask(prompt);
      if (!mounted) return;
      setState(() => _messages.add(_Message(
            text: _formatResult(result),
            user: false,
            plan: result.requiresConfirmation ? result.plan : null,
          )));
    } catch (error) {
      if (mounted) setState(() => _messages.add(_Message(
            text: 'تعذر الاتصال بمساعد Cloudflare.\n$error',
            user: false,
          )));
    } finally {
      if (mounted) setState(() => _loading = false);
      _scrollToEnd();
    }
  }

  String _formatResult(CloudflareAiResult result) {
    if (result.rows.isEmpty) return result.answer;
    final buffer = StringBuffer('${result.answer}\n\n');
    for (final row in result.rows) {
      buffer.writeln(row.entries.map((entry) => '${entry.key}: ${entry.value}').join(' | '));
    }
    return buffer.toString().trim();
  }

  Future<void> _confirm(int index) async {
    final plan = _messages[index].plan;
    if (plan == null || _loading) return;
    setState(() {
      _loading = true;
      _messages[index] = _messages[index].copyWith(text: '${_messages[index].text}\n\n⏳ جاري التنفيذ...');
    });
    try {
      final result = await CloudflareAiService.instance.confirm(plan);
      if (!mounted) return;
      setState(() => _messages[index] = _messages[index].copyWith(
            text: '${_messages[index].text}\n\n✅ ${result.answer}',
            plan: null,
            executed: true,
          ));
    } catch (error) {
      if (mounted) setState(() => _messages[index] = _messages[index].copyWith(text: '${_messages[index].text}\n\n❌ $error'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _cancel(int index) => setState(() => _messages[index] = _messages[index].copyWith(
        text: '${_messages[index].text}\n\n❌ تم الإلغاء.',
        plan: null,
      ));

  void _scrollToEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) unawaited(_scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
            ));
      });

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(
            title: const Row(children: [Icon(Icons.cloud, color: Colors.orange), SizedBox(width: 8), Text('مساعد Cloudflare AI')]),
            actions: [IconButton(onPressed: () => setState(() => _messages.clear()), icon: const Icon(Icons.delete_outline), tooltip: 'مسح المحادثة')],
          ),
          body: Column(children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(12),
                itemCount: _messages.length + (_loading ? 1 : 0),
                itemBuilder: (_, index) {
                  if (index == _messages.length) return const ListTile(leading: CircularProgressIndicator(), title: Text('Cloudflare AI يفكر...'));
                  final message = _messages[index];
                  return Align(
                    alignment: message.user ? Alignment.centerLeft : Alignment.centerRight,
                    child: Card(
                      color: message.user ? Theme.of(context).colorScheme.primaryContainer : null,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(message.text, style: const TextStyle(fontSize: 14, height: 1.5)),
                          if (message.plan != null) ...[
                            const SizedBox(height: 10),
                            const Text('هذه إضافة مالية. راجعها ثم اختر:', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            Row(children: [
                              ElevatedButton.icon(onPressed: () => _confirm(index), icon: const Icon(Icons.check, size: 16), label: const Text('تأكيد التنفيذ')),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(onPressed: () => _cancel(index), icon: const Icon(Icons.close, size: 16), label: const Text('إلغاء')),
                            ]),
                          ],
                        ]),
                      ),
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
                child: Row(children: [
                  Expanded(child: TextField(controller: _controller, minLines: 1, maxLines: 4, onSubmitted: (_) => _send(), decoration: const InputDecoration(hintText: 'اكتب طلبك بالعربية...', border: OutlineInputBorder()))),
                  const SizedBox(width: 8),
                  IconButton.filled(onPressed: _loading ? null : _send, icon: const Icon(Icons.send)),
                ]),
              ),
            ),
          ]),
        ),
      );
}
