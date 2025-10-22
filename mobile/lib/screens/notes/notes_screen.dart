import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/app_scaffold.dart';
import '../../services/sync_service.dart';

/// شاشة إدارة الملاحظات والتنبيهات
class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedFilter = 'all';
  final List<ShiftNote> _notes = _generateSampleNotes();

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
          onPressed: () => ref.read(syncServiceProvider).runSync(),
          icon: const Icon(Icons.sync),
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
          // أشرطة التبويب
          Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceVariant,
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
              unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
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
                _buildNotesList(_notes),
                _buildNotesList(_notes.where((n) => !n.isRead).toList()),
                _buildNotesList(_notes.where((n) => n.priority == NotePriority.high).toList()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotesStats() {
    final unreadCount = _notes.where((n) => !n.isRead).length;
    final highPriorityCount = _notes.where((n) => n.priority == NotePriority.high).length;
    final activeCount = _notes.where((n) => n.status == NoteStatus.active).length;

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
              Expanded(child: _buildStatChip('الإجمالي', _notes.length, Colors.blue)),
              const SizedBox(width: 8),
              Expanded(child: _buildStatChip('غير مقروءة', unreadCount, Colors.orange)),
              const SizedBox(width: 8),
              Expanded(child: _buildStatChip('أولوية عالية', highPriorityCount, Colors.red)),
              const SizedBox(width: 8),
              Expanded(child: _buildStatChip('نشطة', activeCount, Colors.green)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: color.withOpacity(0.8),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
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

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: notes.length,
      itemBuilder: (context, index) {
        final note = notes[index];
        return _buildNoteCard(context, note);
      },
    );
  }

  Widget _buildNoteCard(BuildContext context, ShiftNote note) {
    final priorityColor = _getPriorityColor(note.priority);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border(
            left: BorderSide(color: priorityColor, width: 4),
          ),
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
                  Icon(Icons.access_time, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    _formatDate(note.createdAt),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  if (note.expiresAt != null) ...[
                    const SizedBox(width: 12),
                    Icon(Icons.schedule, size: 14, color: Colors.orange),
                    const SizedBox(width: 4),
                    Text(
                      'ينتهي: ${_formatDate(note.expiresAt!)}',
                      style: const TextStyle(fontSize: 12, color: Colors.orange),
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
        break;
      case NotePriority.medium:
        color = Colors.orange;
        text = 'متوسطة';
        icon = Icons.remove;
        break;
      case NotePriority.low:
        color = Colors.green;
        text = 'منخفضة';
        icon = Icons.keyboard_arrow_down;
        break;
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
        break;
      case ShiftType.evening:
        color = Colors.orange.shade700;
        text = 'مسائي';
        break;
      case ShiftType.night:
        color = Colors.indigo;
        text = 'ليلي';
        break;
      case ShiftType.all:
        color = Colors.purple;
        text = 'جميع النوبات';
        break;
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

  void _markAsRead(ShiftNote note) {
    setState(() {
      note.isRead = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم وضع علامة مقروء')),
    );
  }

  void _deleteNote(BuildContext context, ShiftNote note) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف الملاحظة'),
        content: Text('هل تريد حذف "${note.title}"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _notes.remove(note);
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تم حذف الملاحظة')),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
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
                      value: priority,
                      decoration: const InputDecoration(
                        labelText: 'الأولوية',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: NotePriority.high, child: Text('عالية')),
                        DropdownMenuItem(value: NotePriority.medium, child: Text('متوسطة')),
                        DropdownMenuItem(value: NotePriority.low, child: Text('منخفضة')),
                      ],
                      onChanged: (value) => setState(() => priority = value ?? priority),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<ShiftType>(
                      value: shiftType,
                      decoration: const InputDecoration(
                        labelText: 'النوبة',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: ShiftType.all, child: Text('جميع النوبات')),
                        DropdownMenuItem(value: ShiftType.morning, child: Text('النوبة الصباحية')),
                        DropdownMenuItem(value: ShiftType.evening, child: Text('النوبة المسائية')),
                        DropdownMenuItem(value: ShiftType.night, child: Text('النوبة الليلية')),
                      ],
                      onChanged: (value) => setState(() => shiftType = value ?? shiftType),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      leading: const Icon(Icons.schedule),
                      title: const Text('تاريخ انتهاء الصلاحية'),
                      subtitle: Text(expiresAt?.toString().split(' ')[0] ?? 'غير محدد'),
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
                                initialDate: expiresAt ?? DateTime.now().add(const Duration(days: 7)),
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now().add(const Duration(days: 365)),
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
                onPressed: () {
                  if (titleController.text.trim().isEmpty || contentController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('يرجى تعبئة العنوان والمحتوى')),
                    );
                    return;
                  }

                  if (note == null) {
                    // إضافة ملاحظة جديدة
                    _notes.add(ShiftNote(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      title: titleController.text.trim(),
                      content: contentController.text.trim(),
                      priority: priority,
                      shiftType: shiftType,
                      createdAt: DateTime.now(),
                      expiresAt: expiresAt,
                      isRead: false,
                      status: NoteStatus.active,
                      createdBy: 'current_user',
                    ));
                  } else {
                    // تعديل الملاحظة الموجودة
                    setState(() {
                      note.title = titleController.text.trim();
                      note.content = contentController.text.trim();
                      note.priority = priority;
                      note.shiftType = shiftType;
                      note.expiresAt = expiresAt;
                    });
                  }

                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(note == null ? 'تم إضافة الملاحظة' : 'تم تحديث الملاحظة'),
                    ),
                  );
                },
                child: Text(note == null ? 'إضافة' : 'تحديث'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static List<ShiftNote> _generateSampleNotes() {
    return [
      ShiftNote(
        id: '1',
        title: 'تنبيه: صيانة المصعد',
        content: 'يرجى إبلاغ الضيوف أن المصعد الرئيسي تحت الصيانة من الساعة 2-4 ظهراً',
        priority: NotePriority.high,
        shiftType: ShiftType.all,
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
        expiresAt: DateTime.now().add(const Duration(hours: 6)),
        isRead: false,
        status: NoteStatus.active,
        createdBy: 'admin',
      ),
      ShiftNote(
        id: '2',
        title: 'ملاحظة للنوبة المسائية',
        content: 'يرجى التأكد من تشغيل الإضاءة الخارجية للفندق عند غروب الشمس',
        priority: NotePriority.medium,
        shiftType: ShiftType.evening,
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
        isRead: true,
        status: NoteStatus.active,
        createdBy: 'manager',
      ),
      ShiftNote(
        id: '3',
        title: 'تحديث نظام الحجوزات',
        content: 'تم تحديث نظام الحجوزات. يرجى مراجعة التعليمات الجديدة في دليل المستخدم',
        priority: NotePriority.low,
        shiftType: ShiftType.all,
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
        isRead: false,
        status: NoteStatus.active,
        createdBy: 'it_support',
      ),
    ];
  }
}

// نماذج البيانات
class ShiftNote {
  final String id;
  String title;
  String content;
  NotePriority priority;
  ShiftType shiftType;
  final DateTime createdAt;
  DateTime? expiresAt;
  bool isRead;
  NoteStatus status;
  final String createdBy;

  ShiftNote({
    required this.id,
    required this.title,
    required this.content,
    required this.priority,
    required this.shiftType,
    required this.createdAt,
    this.expiresAt,
    this.isRead = false,
    this.status = NoteStatus.active,
    required this.createdBy,
  });
}

enum NotePriority { high, medium, low }
enum ShiftType { morning, evening, night, all }
enum NoteStatus { active, completed, expired }