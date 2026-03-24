import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/app_scaffold.dart';
import '../../services/sync_service.dart';
import '../../providers/repository_providers.dart';
import '../../models/shift_note_adapter.dart';

final shiftNotesListProvider = StreamProvider.autoDispose(
  (ref) => ref.watch(shiftNotesRepoProvider).watchAll(),
);
final unreadNotesCountProvider = FutureProvider.autoDispose(
  (ref) => ref.watch(shiftNotesRepoProvider).getUnreadCount(),
);
final activeShiftNotesProvider = FutureProvider.autoDispose(
  (ref) => ref.watch(shiftNotesRepoProvider).listAllActive(),
);
final unreadShiftNotesProvider = FutureProvider.autoDispose(
  (ref) => ref.watch(shiftNotesRepoProvider).listUnread(),
);
final highPriorityNotesProvider = FutureProvider.autoDispose(
  (ref) => ref.watch(shiftNotesRepoProvider).listHighPriority(),
);

/// شاشة إدارة الملاحظات والتنبيهات - النسخة المحدثة
class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _errorMessage;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'الملاحظات والتنبيهات',
      actions: [
        IconButton(
          onPressed: () async {
            setState(() => _isProcessing = true);
            try {
              await ref.read(syncServiceProvider).runSync();
              // إعادة تحديث البيانات بعد المزامنة
              ref.invalidate(shiftNotesListProvider);
              ref.invalidate(unreadShiftNotesProvider);
              ref.invalidate(highPriorityNotesProvider);
            } catch (e) {
              setState(() => _errorMessage = 'خطأ في المزامنة: $e');
            } finally {
              setState(() => _isProcessing = false);
            }
          },
          icon: _isProcessing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.sync),
          tooltip: 'مزامنة',
        ),
        IconButton(
          onPressed: () => _showAddNoteDialog(context),
          icon: const Icon(Icons.add),
          tooltip: 'إضافة ملاحظة',
        ),
      ],
      body: Column(
        children: [
          // رسالة خطأ
          if (_errorMessage != null)
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade300),
              ),
              child: Row(
                children: [
                  Icon(Icons.error, color: Colors.red.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(color: Colors.red.shade700),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _errorMessage = null),
                    color: Colors.red.shade700,
                  ),
                ],
              ),
            ),

          // أشرطة التبويب
          Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(25),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                borderRadius: BorderRadius.circular(25),
                color: Theme.of(context).colorScheme.primary,
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: Theme.of(context).colorScheme.onPrimary,
              unselectedLabelColor: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant,
              dividerColor: Colors.transparent,
              tabs: const [
                Tab(text: 'جميع الملاحظات'),
                Tab(text: 'غير مقروءة'),
                Tab(text: 'عالية الأولوية'),
              ],
            ),
          ),

          // إحصائيات الملاحظات
          _buildNotesStats(),

          const SizedBox(height: 16),

          // قائمة الملاحظات
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildAllNotesTab(),
                _buildUnreadNotesTab(),
                _buildHighPriorityNotesTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotesStats() {
    return Consumer(
      builder: (context, ref, _) {
        final unreadCountAsync = ref.watch(unreadNotesCountProvider);
        final highPriorityAsync = ref.watch(highPriorityNotesProvider);
        final allNotesAsync = ref.watch(activeShiftNotesProvider);

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue.shade50, Colors.blue.shade100],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.analytics, color: Colors.blue, size: 24),
                  SizedBox(width: 8),
                  Text(
                    'إحصائيات الملاحظات',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildStatChip(
                      'الإجمالي',
                      allNotesAsync.when(
                        data: (notes) => notes.length,
                        loading: () => null,
                        error: (_, __) => 0,
                      ),
                      Colors.blue,
                      isLoading: allNotesAsync.isLoading,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildStatChip(
                      'غير مقروءة',
                      unreadCountAsync.when(
                        data: (count) => count,
                        loading: () => null,
                        error: (_, __) => 0,
                      ),
                      Colors.orange,
                      isLoading: unreadCountAsync.isLoading,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildStatChip(
                      'أولوية عالية',
                      highPriorityAsync.when(
                        data: (notes) => notes.length,
                        loading: () => null,
                        error: (_, __) => 0,
                      ),
                      Colors.red,
                      isLoading: highPriorityAsync.isLoading,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildStatChip(
                      'نشطة',
                      allNotesAsync.when(
                        data: (notes) => notes
                            .where((n) => n.status == NoteStatus.active)
                            .length,
                        loading: () => null,
                        error: (_, __) => 0,
                      ),
                      Colors.green,
                      isLoading: allNotesAsync.isLoading,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatChip(
    String label,
    int? count,
    Color color, {
    bool isLoading = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          if (isLoading)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            )
          else
            Text(
              count?.toString() ?? '0',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(fontSize: 10, color: color.withOpacity(0.8)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildAllNotesTab() {
    return Consumer(
      builder: (context, ref, _) {
        final notesAsync = ref.watch(activeShiftNotesProvider);

        return notesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error, size: 64, color: Colors.red.shade400),
                const SizedBox(height: 16),
                Text(
                  'خطأ في تحميل الملاحظات',
                  style: TextStyle(fontSize: 18, color: Colors.red.shade700),
                ),
                const SizedBox(height: 8),
                Text(
                  error.toString(),
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => ref.invalidate(activeShiftNotesProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          ),
          data: _buildNotesList,
        );
      },
    );
  }

  Widget _buildUnreadNotesTab() {
    return Consumer(
      builder: (context, ref, _) {
        final notesAsync = ref.watch(unreadShiftNotesProvider);

        return notesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error, size: 64, color: Colors.red.shade400),
                const SizedBox(height: 16),
                Text(
                  'خطأ في تحميل الملاحظات غير المقروءة',
                  style: TextStyle(fontSize: 18, color: Colors.red.shade700),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => ref.invalidate(unreadShiftNotesProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          ),
          data: _buildNotesList,
        );
      },
    );
  }

  Widget _buildHighPriorityNotesTab() {
    return Consumer(
      builder: (context, ref, _) {
        final notesAsync = ref.watch(highPriorityNotesProvider);

        return notesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error, size: 64, color: Colors.red.shade400),
                const SizedBox(height: 16),
                Text(
                  'خطأ في تحميل الملاحظات عالية الأولوية',
                  style: TextStyle(fontSize: 18, color: Colors.red.shade700),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => ref.invalidate(highPriorityNotesProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          ),
          data: _buildNotesList,
        );
      },
    );
  }

  Widget _buildNotesList(List<ShiftNote> notes) {
    if (notes.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.note_alt_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('لا توجد ملاحظات', style: TextStyle(fontSize: 18)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(activeShiftNotesProvider);
        ref.invalidate(unreadShiftNotesProvider);
        ref.invalidate(highPriorityNotesProvider);
        ref.invalidate(unreadNotesCountProvider);
      },
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: notes.length,
        itemBuilder: (context, index) {
          final note = notes[index];
          return _buildNoteCard(context, note);
        },
      ),
    );
  }

  Widget _buildNoteCard(BuildContext context, ShiftNote note) {
    final priorityColor = _getPriorityColor(note.priority);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border(left: BorderSide(color: priorityColor, width: 4)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // رأس الملاحظة
              Row(
                children: [
                  Expanded(
                    child: Text(
                      note.title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: note.isRead ? Colors.grey : Colors.black,
                      ),
                    ),
                  ),
                  _buildPriorityBadge(note.priority),
                  const SizedBox(width: 8),
                  _buildShiftBadge(note.shiftType),
                ],
              ),

              const SizedBox(height: 8),

              // محتوى الملاحظة
              Text(
                note.content,
                style: TextStyle(
                  fontSize: 14,
                  color: note.isRead ? Colors.grey : Colors.black87,
                  height: 1.4,
                ),
              ),

              const SizedBox(height: 12),

              // تفاصيل إضافية
              Row(
                children: [
                  const Icon(Icons.access_time, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    _formatDate(note.createdAt),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  if (note.expiresAt != null) ...[
                    const SizedBox(width: 12),
                    const Icon(Icons.schedule, size: 14, color: Colors.orange),
                    const SizedBox(width: 4),
                    Text(
                      'ينتهي: ${_formatDate(note.expiresAt!)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.orange,
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (!note.isRead)
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 12),

              // أزرار العمليات
              Row(
                children: [
                  if (!note.isRead)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _markAsRead(note),
                        icon: const Icon(Icons.visibility, size: 16),
                        label: const Text('وضع علامة مقروء'),
                      ),
                    ),
                  if (!note.isRead) const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _showEditNoteDialog(context, note),
                      icon: const Icon(Icons.edit, size: 16),
                      label: const Text('تعديل'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => _deleteNote(context, note),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                    ),
                    child: const Icon(Icons.delete, size: 16),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPriorityBadge(NotePriority priority) {
    Color color;
    String text;
    IconData icon;

    switch (priority) {
      case NotePriority.high:
        color = Colors.red;
        text = 'عالية';
        icon = Icons.priority_high;
      case NotePriority.medium:
        color = Colors.orange;
        text = 'متوسطة';
        icon = Icons.remove;
      case NotePriority.low:
        color = Colors.green;
        text = 'منخفضة';
        icon = Icons.keyboard_arrow_down;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 2),
          Text(
            text,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShiftBadge(ShiftType shiftType) {
    Color color;
    String text;

    switch (shiftType) {
      case ShiftType.morning:
        color = Colors.yellow.shade700;
        text = 'صباحي';
      case ShiftType.evening:
        color = Colors.orange.shade700;
        text = 'مسائي';
      case ShiftType.night:
        color = Colors.indigo;
        text = 'ليلي';
      case ShiftType.all:
        color = Colors.purple;
        text = 'جميع النوبات';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Color _getPriorityColor(NotePriority priority) {
    switch (priority) {
      case NotePriority.high:
        return Colors.red;
      case NotePriority.medium:
        return Colors.orange;
      case NotePriority.low:
        return Colors.green;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _markAsRead(ShiftNote note) async {
    setState(() => _isProcessing = true);
    try {
      final success =
          await ref.read(shiftNotesRepoProvider).markAsRead(note.id);
      if (success) {
        // إعادة تحديث البيانات
        ref.invalidate(activeShiftNotesProvider);
        ref.invalidate(unreadShiftNotesProvider);
        ref.invalidate(unreadNotesCountProvider);

        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('تم وضع علامة مقروء')));
        }
      } else {
        setState(() => _errorMessage = 'فشل في تحديث الملاحظة');
      }
    } catch (e) {
      setState(() => _errorMessage = 'خطأ في تحديث الملاحظة: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _deleteNote(BuildContext context, ShiftNote note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف الملاحظة'),
        content: Text('هل تريد حذف "${note.title}"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if ((confirmed ?? false) && mounted) {
      setState(() => _isProcessing = true);
      try {
        final success = await ref.read(shiftNotesRepoProvider).delete(note.id);
        if (success) {
          // إعادة تحديث البيانات
          ref.invalidate(activeShiftNotesProvider);
          ref.invalidate(unreadShiftNotesProvider);
          ref.invalidate(highPriorityNotesProvider);
          ref.invalidate(unreadNotesCountProvider);

          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('تم حذف الملاحظة')));
          }
        } else {
          setState(() => _errorMessage = 'فشل في حذف الملاحظة');
        }
      } catch (e) {
        setState(() => _errorMessage = 'خطأ في حذف الملاحظة: $e');
      } finally {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _showAddNoteDialog(BuildContext context) {
    _showNoteDialog(context, null);
  }

  void _showEditNoteDialog(BuildContext context, ShiftNote note) {
    _showNoteDialog(context, note);
  }

  void _showNoteDialog(BuildContext context, ShiftNote? note) {
    final titleController = TextEditingController(text: note?.title ?? '');
    final contentController = TextEditingController(text: note?.content ?? '');
    NotePriority priority = note?.priority ?? NotePriority.medium;
    ShiftType shiftType = note?.shiftType ?? ShiftType.all;
    DateTime? expiresAt = note?.expiresAt;

    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text(note == null ? 'إضافة ملاحظة جديدة' : 'تعديل الملاحظة'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        labelText: 'عنوان الملاحظة*',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: contentController,
                      decoration: const InputDecoration(
                        labelText: 'محتوى الملاحظة*',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<NotePriority>(
                      initialValue: priority,
                      decoration: const InputDecoration(
                        labelText: 'الأولوية',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: NotePriority.high,
                          child: Text('عالية'),
                        ),
                        DropdownMenuItem(
                          value: NotePriority.medium,
                          child: Text('متوسطة'),
                        ),
                        DropdownMenuItem(
                          value: NotePriority.low,
                          child: Text('منخفضة'),
                        ),
                      ],
                      onChanged: (value) =>
                          setState(() => priority = value ?? priority),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<ShiftType>(
                      initialValue: shiftType,
                      decoration: const InputDecoration(
                        labelText: 'النوبة',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: ShiftType.all,
                          child: Text('جميع النوبات'),
                        ),
                        DropdownMenuItem(
                          value: ShiftType.morning,
                          child: Text('النوبة الصباحية'),
                        ),
                        DropdownMenuItem(
                          value: ShiftType.evening,
                          child: Text('النوبة المسائية'),
                        ),
                        DropdownMenuItem(
                          value: ShiftType.night,
                          child: Text('النوبة الليلية'),
                        ),
                      ],
                      onChanged: (value) =>
                          setState(() => shiftType = value ?? shiftType),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      leading: const Icon(Icons.schedule),
                      title: const Text('تاريخ انتهاء الصلاحية'),
                      subtitle: Text(
                        expiresAt?.toString().split(' ')[0] ?? 'غير محدد',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (expiresAt != null)
                            IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () => setState(() => expiresAt = null),
                            ),
                          IconButton(
                            icon: const Icon(Icons.calendar_today),
                            onPressed: () async {
                              final date = await showDatePicker(
                                context: context,
                                initialDate: expiresAt ??
                                    DateTime.now().add(const Duration(days: 7)),
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now().add(
                                  const Duration(days: 365),
                                ),
                              );
                              if (date != null) {
                                setState(() => expiresAt = date);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () => _saveNote(
                  context,
                  note,
                  titleController.text,
                  contentController.text,
                  priority,
                  shiftType,
                  expiresAt,
                ),
                child: Text(note == null ? 'إضافة' : 'تحديث'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveNote(
    BuildContext context,
    ShiftNote? existingNote,
    String title,
    String content,
    NotePriority priority,
    ShiftType shiftType,
    DateTime? expiresAt,
  ) async {
    if (title.trim().isEmpty || content.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى تعبئة العنوان والمحتوى')),
      );
      return;
    }

    Navigator.pop(context); // إغلاق الحوار أولاً
    setState(() => _isProcessing = true);

    try {
      if (existingNote == null) {
        // إنشاء ملاحظة جديدة
        final newNote = ShiftNote(
          id: '0', // سيتم تعيين ID جديد من قاعدة البيانات
          title: title.trim(),
          content: content.trim(),
          priority: priority,
          shiftType: shiftType,
          createdAt: DateTime.now(),
          expiresAt: expiresAt,
          isRead: false,
          status: NoteStatus.active,
          createdBy: 'current_user',
        );

        await ref.read(shiftNotesRepoProvider).create(newNote);

        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('تم إضافة الملاحظة')));
        }
      } else {
        // تحديث ملاحظة موجودة
        final updatedNote = ShiftNote(
          id: existingNote.id,
          title: title.trim(),
          content: content.trim(),
          priority: priority,
          shiftType: shiftType,
          createdAt: existingNote.createdAt,
          expiresAt: expiresAt,
          isRead: existingNote.isRead,
          status: existingNote.status,
          createdBy: existingNote.createdBy,
        );

        final success =
            await ref.read(shiftNotesRepoProvider).update(updatedNote);

        if (success && mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('تم تحديث الملاحظة')));
        } else if (!success) {
          setState(() => _errorMessage = 'فشل في تحديث الملاحظة');
        }
      }

      // إعادة تحديث البيانات
      ref.invalidate(activeShiftNotesProvider);
      ref.invalidate(unreadShiftNotesProvider);
      ref.invalidate(highPriorityNotesProvider);
      ref.invalidate(unreadNotesCountProvider);
    } catch (e) {
      setState(() => _errorMessage = 'خطأ في حفظ الملاحظة: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }
}
