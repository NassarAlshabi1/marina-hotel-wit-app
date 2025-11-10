import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/app_scaffold.dart';
import '../../services/google_drive_backup_service.dart';
import '../../services/session_state_manager.dart';

/// شاشة إدارة جلسات التطبيق في Google Drive
/// 
/// تتيح للمستخدم:
/// - حفظ الجلسة الحالية في Google Drive
/// - استعادة جلسة محفوظة
/// - عرض قائمة الجلسات المحفوظة
/// - حذف الجلسات القديمة
class SessionManagementScreen extends ConsumerStatefulWidget {
  const SessionManagementScreen({super.key});

  @override
  ConsumerState<SessionManagementScreen> createState() => _SessionManagementScreenState();
}

class _SessionManagementScreenState extends ConsumerState<SessionManagementScreen> {
  final _driveService = GoogleDriveBackupService();
  final _sessionManager = SessionStateManager();
  
  bool _isLoading = false;
  bool _isSignedIn = false;
  List<SessionInfo> _availableSessions = [];
  Map<String, String>? _lastSavedSession;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    setState(() => _isLoading = true);

    try {
      // محاولة استعادة الجلسة ثم التحقق من حالة تسجيل الدخول
      await _driveService.attemptSilentSignIn();
      _isSignedIn = _driveService.isSignedIn;
      
      if (_isSignedIn) {
        // جلب الجلسات المحفوظة
        await _loadSessions();
      }
      
      // جلب معلومات آخر جلسة محفوظة
      _lastSavedSession = await _sessionManager.getLastSavedSessionInfo();
      
    } catch (e) {
      debugPrint('خطأ في التهيئة: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadSessions() async {
    try {
      final sessions = await _sessionManager.getAvailableSessions(
        driveService: _driveService,
      );
      
      if (mounted) {
        setState(() => _availableSessions = sessions);
      }
    } catch (e) {
      debugPrint('خطأ في جلب الجلسات: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'إدارة جلسات التطبيق',
      actions: [
        if (_isSignedIn)
          IconButton(
            onPressed: _isLoading ? null : _loadSessions,
            icon: const Icon(Icons.refresh),
            tooltip: 'تحديث',
          ),
      ],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : !_isSignedIn
              ? _buildSignInRequired()
              : _buildSessionsContent(),
    );
  }

  Widget _buildSignInRequired() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 24),
          const Text(
            'يجب تسجيل الدخول إلى Google Drive',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'قم بتسجيل الدخول لحفظ واستعادة جلسات التطبيق',
            style: TextStyle(color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: _signInToDrive,
            icon: const Icon(Icons.login),
            label: const Text('تسجيل الدخول إلى Google Drive'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionsContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // بطاقة معلومات
          _buildInfoCard(),
          const SizedBox(height: 16),
          
          // أزرار الإجراءات
          _buildActionButtons(),
          const SizedBox(height: 16),
          
          // آخر جلسة محفوظة
          if (_lastSavedSession != null) ...[
            _buildLastSavedSession(),
            const SizedBox(height: 16),
          ],
          
          // قائمة الجلسات المحفوظة
          _buildSessionsList(),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue.shade600),
                const SizedBox(width: 12),
                const Text(
                  'حول جلسات التطبيق',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'تسمح لك جلسات التطبيق بحفظ إعداداتك الحالية واستعادتها في أي وقت أو على أجهزة أخرى. تشمل:',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 8),
            _buildInfoItem('إعدادات العرض والموضوع'),
            _buildInfoItem('تفضيلات النسخ الاحتياطي'),
            _buildInfoItem('إعدادات المزامنة'),
            _buildInfoItem('آخر شاشة مستخدمة'),
            _buildInfoItem('إعدادات التقارير'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                border: Border.all(color: Colors.amber.shade200),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, color: Colors.amber.shade700, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'لا يتم حفظ البيانات (الحجوزات، الغرف، إلخ) - فقط الإعدادات',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.amber.shade900,
                      ),
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

  Widget _buildInfoItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(right: 24, top: 4),
      child: Row(
        children: [
          Icon(Icons.check_circle, size: 16, color: Colors.green.shade600),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.settings, color: Colors.teal.shade600),
                const SizedBox(width: 12),
                const Text(
                  'إجراءات الجلسة',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _saveCurrentSession,
                    icon: const Icon(Icons.save),
                    label: const Text('حفظ الجلسة الحالية'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _signOutFromDrive,
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('تسجيل الخروج من Drive'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLastSavedSession() {
    final fileName = _lastSavedSession!['fileName']!;
    final savedAt = DateTime.parse(_lastSavedSession!['savedAt']!);
    
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.blue.shade100,
              child: Icon(Icons.history, color: Colors.blue.shade700),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'آخر جلسة محفوظة',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    fileName,
                    style: const TextStyle(fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${savedAt.day}/${savedAt.month}/${savedAt.year} - ${savedAt.hour}:${savedAt.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
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

  Widget _buildSessionsList() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.folder_open, color: Colors.orange.shade600),
                const SizedBox(width: 12),
                const Text(
                  'الجلسات المحفوظة',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  '(${_availableSessions.length})',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            if (_availableSessions.isEmpty)
              Center(
                child: Column(
                  children: [
                    Icon(Icons.cloud_queue, size: 48, color: Colors.grey.shade400),
                    const SizedBox(height: 8),
                    Text(
                      'لا توجد جلسات محفوظة',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _availableSessions.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final session = _availableSessions[index];
                  return _buildSessionItem(session);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionItem(SessionInfo session) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.purple.shade100,
          child: Icon(Icons.folder, color: Colors.purple.shade700),
        ),
        title: Text(
          session.fileName,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(session.formattedDate, style: const TextStyle(fontSize: 11)),
            Text(session.formattedSize, style: const TextStyle(fontSize: 10)),
          ],
        ),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: () => _restoreSession(session),
              icon: const Icon(Icons.restore, size: 20),
              tooltip: 'استعادة',
              color: Colors.blue,
            ),
            IconButton(
              onPressed: () => _deleteSession(session),
              icon: const Icon(Icons.delete, size: 20),
              tooltip: 'حذف',
              color: Colors.red,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _signInToDrive() async {
    setState(() => _isLoading = true);

    try {
      final account = await _driveService.signInForDrive();
      
      if (account != null && mounted) {
        setState(() => _isSignedIn = _driveService.isSignedIn);
        await _loadSessions();
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تم تسجيل الدخول بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ خطأ في تسجيل الدخول: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _signOutFromDrive() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد تسجيل الخروج'),
        content: const Text('هل أنت متأكد من تسجيل الخروج من Google Drive؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('تسجيل الخروج'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _driveService.signOut();
      setState(() {
        _isSignedIn = false;
        _availableSessions.clear();
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تسجيل الخروج بنجاح'),
          ),
        );
      }
    }
  }

  Future<void> _saveCurrentSession() async {
    final nameController = TextEditingController();
    
    final sessionName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حفظ الجلسة الحالية'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'اسم الجلسة (اختياري)',
            hintText: 'مثال: إعدادات العمل',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, nameController.text.trim()),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );

    if (sessionName == null && mounted) return;

    setState(() => _isLoading = true);

    try {
      final saved = await _sessionManager.saveSessionToDrive(
        driveService: _driveService,
        sessionName: (sessionName ?? '').isEmpty ? null : sessionName,
      );
      
      if (saved && mounted) {
        await _loadSessions();
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تم حفظ الجلسة بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        throw Exception('فشل في الحفظ');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ خطأ في حفظ الجلسة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _restoreSession(SessionInfo session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('استعادة الجلسة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('هل تريد استعادة هذه الجلسة؟'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                border: Border.all(color: Colors.amber.shade200),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning, color: Colors.amber.shade700, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'سيتم استبدال إعداداتك الحالية',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('استعادة'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isLoading = true);

    try {
      final restored = await _sessionManager.restoreSessionFromDrive(
        driveService: _driveService,
        fileName: session.fileName,
      );
      
      if (restored && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تم استعادة الجلسة بنجاح - أعد تشغيل التطبيق'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 5),
          ),
        );
      } else {
        throw Exception('فشل في الاستعادة');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ خطأ في استعادة الجلسة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _deleteSession(SessionInfo session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف الجلسة'),
        content: Text('هل تريد حذف "${session.fileName}"؟'),
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

    if (confirmed != true || !mounted) return;

    setState(() => _isLoading = true);

    try {
      final deleted = await _sessionManager.deleteSession(
        driveService: _driveService,
        fileId: session.fileId,
      );
      
      if (deleted && mounted) {
        await _loadSessions();
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تم حذف الجلسة بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        throw Exception('فشل في الحذف');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ خطأ في حذف الجلسة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}
