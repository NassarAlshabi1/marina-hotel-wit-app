import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/app_scaffold.dart';
import '../../services/providers.dart';
import '../../services/local_db.dart';

/// شاشة الملاحظات البسيطة
class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> 
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

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
          onPressed: _addNote,
          icon: const Icon(Icons.add),
          tooltip: 'إضافة ملاحظة',
        ),
      ],
      body: Column(
        children: [
          // أشرطة التبويب
          _buildTabs(),
          
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

  Widget _buildTabs() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(25),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(25),
          color: Colors.blue,
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.grey.shade600,
        dividerColor: Colors.transparent,
        tabs: const [
          Tab(text: 'الكل'),
          Tab(text: 'غير مقروءة'),
          Tab(text: 'مهمة'),
        ],
      ),
    );
  }

  Widget _buildAllNotesTab() {
    return Consumer(
      builder: (context, ref, _) {
        final notesAsync = ref.watch(simpleNotesListProvider);
        return notesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('خطأ: $e')),
          data: (notes) => _buildNotesList(notes),
        );
      },
    );
  }

  Widget _buildUnreadNotesTab() {
    return Consumer(
      builder: (context, ref, _) {
        final notesAsync = ref.watch(simpleNotesUnreadListProvider);
        return notesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('خطأ: $e')),
          data: (notes) => _buildNotesList(notes),
        );
      },
    );
  }

  Widget _buildHighPriorityNotesTab() {
    return Consumer(
      builder: (context, ref, _) {
        final notesAsync = ref.watch(simpleNotesHighPriorityListProvider);
        return notesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('خطأ: $e')),
          data: (notes) => _buildNotesList(notes),
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
            Text('لا توجد ملاحظات'),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: notes.length,
      itemBuilder: (context, index) {
        final note = notes[index];
        return _buildNoteCard(note);
      },
    );
  }

  Widget _buildNoteCard(ShiftNote note) {
    final priorityColor = note.priority == 'high' ? Colors.red :
                         note.priority == 'medium' ? Colors.orange : Colors.green;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Container(
          width: 4,
          height: 50,
          color: priorityColor,
        ),
        title: Text(
          note.title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: note.isRead == 1 ? Colors.grey : Colors.black,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(note.content),
            const SizedBox(height: 4),
            Text(
              _formatDate(DateTime.parse(note.createdAt)),
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (note.isRead == 0)
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.blue,
                  shape: BoxShape.circle,
                ),
              ),
            PopupMenuButton(
              itemBuilder: (context) => [
                if (note.isRead == 0)
                  const PopupMenuItem(
                    value: 'read',
                    child: Text('وضع علامة مقروء'),
                  ),
                const PopupMenuItem(
                  value: 'edit',
                  child: Text('تعديل'),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('حذف'),
                ),
              ],
              onSelected: (value) => _handleNoteAction(value, note),
            ),
          ],
        ),
      ),
    );
  }

  void _handleNoteAction(String action, ShiftNote note) async {
    final repo = ref.read(simpleNotesRepoProvider);
    
    switch (action) {
      case 'read':
        await repo.markAsRead(note.id);
        break;
      case 'edit':
        _editNote(note);
        break;
      case 'delete':
        _deleteNote(note);
        break;
    }
  }

  void _addNote() {
    _showNoteDialog();
  }

  void _editNote(ShiftNote note) {
    _showNoteDialog(note: note);
  }

  void _deleteNote(ShiftNote note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف الملاحظة'),
        content: const Text('هل تريد حذف هذه الملاحظة؟'),
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

    if (confirmed == true) {
      await ref.read(simpleNotesRepoProvider).deleteNote(note.id);
    }
  }

  void _showNoteDialog({ShiftNote? note}) {
    final titleController = TextEditingController(text: note?.title ?? '');
    final contentController = TextEditingController(text: note?.content ?? '');
    String priority = note?.priority ?? 'medium';
    String shiftType = note?.shiftType ?? 'all';

    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(note == null ? 'إضافة ملاحظة' : 'تعديل الملاحظة'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: 'العنوان',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contentController,
                decoration: const InputDecoration(
                  labelText: 'المحتوى',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: priority,
                decoration: const InputDecoration(
                  labelText: 'الأولوية',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'low', child: Text('منخفضة')),
                  DropdownMenuItem(value: 'medium', child: Text('متوسطة')),
                  DropdownMenuItem(value: 'high', child: Text('عالية')),
                ],
                onChanged: (value) => priority = value ?? priority,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () {
                if (titleController.text.trim().isNotEmpty &&
                    contentController.text.trim().isNotEmpty) {
                  _saveNote(
                    note,
                    titleController.text.trim(),
                    contentController.text.trim(),
                    priority,
                    shiftType,
                  );
                  Navigator.pop(context);
                }
              },
              child: Text(note == null ? 'إضافة' : 'تحديث'),
            ),
          ],
        ),
      ),
    );
  }

  void _saveNote(ShiftNote? note, String title, String content, 
                String priority, String shiftType) async {
    final repo = ref.read(simpleNotesRepoProvider);
    
    if (note == null) {
      // إضافة جديدة
      await repo.addNote(
        title: title,
        content: content,
        priority: priority,
        shiftType: shiftType,
      );
    } else {
      // تحديث موجود
      await repo.updateNote(
        note.id,
        title: title,
        content: content,
        priority: priority,
        shiftType: shiftType,
      );
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}