import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/appwrite_providers.dart';
import '../providers/repository_providers.dart';
import '../services/daos/outbox_dao.dart';
import '../services/appwrite_delta_sync.dart';
import '../services/sync_core/conflict_resolver.dart';
import '../screens/settings/google_drive_backup_screen.dart';

class DashboardSyncButton extends ConsumerStatefulWidget {
  const DashboardSyncButton({super.key});

  @override
  ConsumerState<DashboardSyncButton> createState() =>
      _DashboardSyncButtonState();
}

class _DashboardSyncButtonState extends ConsumerState<DashboardSyncButton>
    with SingleTickerProviderStateMixin {
  bool _isUploading = false;
  bool _appwriteEnabled = true;
  Timer? _pendingChangesTimer;
  late AnimationController _uploadAnimationController;
  int _pendingChangesCount = 0;
  DateTime? _lastUploadTime;

  @override
  void initState() {
    super.initState();
    _uploadAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _loadPendingChangesCount();
    _loadAppwriteEnabled();

    _pendingChangesTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && !_isUploading) {
        _loadPendingChangesCount();
        _loadAppwriteEnabled();
      }
    });
  }

  @override
  void dispose() {
    _pendingChangesTimer?.cancel();
    _uploadAnimationController.dispose();
    super.dispose();
  }

  Future<void> _loadPendingChangesCount() async {
    try {
      final db = ref.read(databaseProvider);
      final outboxDao = OutboxDao(db);
      final count = await outboxDao.count();
      if (mounted) {
        setState(() {
          _pendingChangesCount = count;
        });
      }
    } catch (e) {
      debugPrint('❌ خطأ في تحميل عدد التغييرات المعلقة: $e');
    }
  }

  Future<bool> _isAppwriteSyncEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('appwrite_sync_enabled') ?? false;
  }

  Future<void> _loadAppwriteEnabled() async {
    try {
      final enabled = await _isAppwriteSyncEnabled();
      if (mounted) {
        setState(() => _appwriteEnabled = enabled);
      } else {
        _appwriteEnabled = enabled;
      }
    } catch (e) {
      debugPrint('❌ خطأ في تحميل حالة Appwrite: $e');
      if (mounted) {
        setState(() => _appwriteEnabled = true);
      } else {
        _appwriteEnabled = true;
      }
    }
  }

  Future<void> _uploadChanges(BuildContext context) async {
    if (_isUploading) return;

    if (_pendingChangesCount == 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_outline, color: Colors.white),
                SizedBox(width: 8),
                Text('✅ لا توجد تغييرات جديدة للرفع'),
              ],
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    _uploadAnimationController.repeat();
    if (mounted) {
      setState(() => _isUploading = true);
    } else {
      _isUploading = true;
    }

    try {
      final smartSyncManager = ref.read(smartSyncManagerProvider);
      final appwriteSyncManager = ref.read(appwriteSyncManagerProvider);

      final smartEnabled = await smartSyncManager.isEnabled();
      final isGoogleDriveSignedIn = ref.read(
        smartSyncGoogleDriveSignInStatusProvider,
      );
      final appwriteEnabled = await _isAppwriteSyncEnabled();

      if (!smartEnabled && !appwriteEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.white),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'ℹ️ المزامنة معطلة - يرجى تفعيلها من الإعدادات',
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      if (smartEnabled && !isGoogleDriveSignedIn) {
        if (appwriteEnabled) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Google Drive غير متصل - سيتم استخدام Appwrite'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 3),
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: const [
                    Icon(Icons.cloud_off, color: Colors.white),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '⚠️ يرجى تسجيل الدخول إلى Google Drive أولاً',
                      ),
                    ),
                  ],
                ),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 3),
                action: SnackBarAction(
                  label: 'تسجيل الدخول',
                  textColor: Colors.white,
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const GoogleDriveBackupScreen(),
                      ),
                    );
                  },
                ),
              ),
            );
          }
          return;
        }
      }

      bool appwriteConnected = false;
      if (appwriteEnabled) {
        await ref.read(connectionStatusProvider.notifier).checkConnection();
        appwriteConnected = ref.read(connectionStatusProvider).isConnected;
      }

      final targets = <String>[];
      if (smartEnabled && isGoogleDriveSignedIn) targets.add('Google Drive');
      if (appwriteEnabled && appwriteConnected) targets.add('Appwrite');

      if (targets.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('لا توجد وجهات مزامنة متاحة حالياً'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      if (appwriteEnabled && !appwriteConnected && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Appwrite غير متصل - تم تخطيه'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }

      final targetText = targets.join(' + ');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '🔄 جاري المزامنة الكاملة مع $targetText...',
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 5),
          ),
        );
      }

      final results = <String, Map<String, dynamic>>{};

      // 🔄 ترتيب المزامنة: Pull أولاً ← Resolve ← Push
      // نسحب أولاً حتى لا نكتب فوق تغييرات أحدث

      if (appwriteEnabled && appwriteConnected) {
        try {
          final deltaSync = AppwriteDeltaSync.instance;
          if (deltaSync.isInitialized) {
            // 1️⃣ PULL: سحب التغييرات من السيرفر أولاً
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('⬇️ جاري سحب التغييرات من السيرفر...'),
                  backgroundColor: Colors.blue.shade700,
                  duration: Duration(seconds: 3),
                ),
              );
            }
            final pullResult = await deltaSync.pullDeltaChanges();
            final pulledCount = pullResult.recordsPulled;

            // 2️⃣ RESOLVE: حل التعارضات إن وجدت
            int conflictsResolved = 0;
            if (pullResult.hasConflicts) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('⚖️ جاري حل التعارضات...'),
                    backgroundColor: Colors.orange,
                    duration: Duration(seconds: 2),
                  ),
                );
              }
              conflictsResolved = await _resolveConflicts();
            }

            // 3️⃣ PUSH: رفع التغييرات المحلية
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('⬆️ جاري رفع التغييرات المحلية...'),
                  backgroundColor: Colors.blue.shade700,
                  duration: Duration(seconds: 3),
                ),
              );
            }
            final pushResult = await deltaSync.pushDeltaChanges();
            final pushedCount = pushResult.recordsPushed;

            results['Appwrite'] = {
              'success': pushResult.success && pullResult.success,
              'pulled': pulledCount,
              'pushed': pushedCount,
              'conflicts': conflictsResolved,
            };
          } else {
            // Fallback: push فقط إذا لم يكن DeltaSync مهيأ
            final result = await appwriteSyncManager.pushLocalChanges();
            results['Appwrite'] = {
              'success': result,
              'pulled': 0,
              'pushed': _pendingChangesCount,
              'conflicts': 0,
            };
          }
        } catch (e) {
          results['Appwrite'] = {
            'success': false,
            'pulled': 0,
            'pushed': 0,
            'conflicts': 0,
            'error': e.toString(),
          };
          debugPrint('❌ خطأ في مزامنة Appwrite: $e');
        }
      }

      // Google Drive: بعد Appwrite حتى لا يتعارض
      if (smartEnabled && isGoogleDriveSignedIn) {
        try {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('☁️ جاري مزامنة Google Drive...'),
                backgroundColor: Colors.purple.shade700,
                duration: Duration(seconds: 3),
              ),
            );
          }
          // SmartSyncManager يقوم بـ Pull + Push داخلياً
          final result = await smartSyncManager.syncNow();
          results['Google Drive'] = {
            'success': result,
            'pulled': 0,
            'pushed': _pendingChangesCount,
            'conflicts': 0,
          };
        } catch (e) {
          results['Google Drive'] = {
            'success': false,
            'pulled': 0,
            'pushed': 0,
            'conflicts': 0,
            'error': e.toString(),
          };
          debugPrint('❌ خطأ في مزامنة Google Drive: $e');
        }
      }

      if (mounted) {
        setState(() {
          _lastUploadTime = DateTime.now();
        });
      } else {
        _lastUploadTime = DateTime.now();
      }

      await _loadPendingChangesCount();

      // حساب الإحصائيات الإجمالية
      int totalPulled = 0;
      int totalPushed = 0;
      int totalConflicts = 0;
      final successTargets = <String>[];
      final failedTargets = <String>[];

      for (final entry in results.entries) {
        final data = entry.value;
        if (data['success'] == true) {
          successTargets.add(entry.key);
          totalPulled += (data['pulled'] as int?) ?? 0;
          totalPushed += (data['pushed'] as int?) ?? 0;
          totalConflicts += (data['conflicts'] as int?) ?? 0;
        } else {
          failedTargets.add(entry.key);
        }
      }

      if (mounted) {
        if (failedTargets.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.cloud_done, color: Colors.white),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '✅ تمت المزامنة بنجاح!',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 4),
                  Text(
                    '⬇️ استُلِم: $totalPulled  |  ⬆️ أُرسل: $totalPushed  |  ⚖️ تعارضات: $totalConflicts',
                    style: TextStyle(fontSize: 12),
                  ),
                  Text(
                    '☁️ عبر: ${successTargets.join(' + ')}',
                    style: TextStyle(fontSize: 11),
                  ),
                ],
              ),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 4),
            ),
          );
        } else if (successTargets.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.white),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '❌ فشلت المزامنة مع ${failedTargets.join(' + ')}',
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 4),
              action: SnackBarAction(
                label: 'إعادة',
                textColor: Colors.white,
                onPressed: () => _uploadChanges(context),
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.warning, color: Colors.white),
                      SizedBox(width: 8),
                      Text('⚠️ نجح جزئياً'),
                    ],
                  ),
                  SizedBox(height: 4),
                  Text(
                    '✅ نجح: ${successTargets.join(', ')}',
                    style: TextStyle(fontSize: 12),
                  ),
                  Text(
                    '❌ فشل: ${failedTargets.join(', ')}',
                    style: TextStyle(fontSize: 12),
                  ),
                  if (totalPulled > 0 || totalPushed > 0 || totalConflicts > 0)
                    Text(
                      '⬇️ $totalPulled  ⬆️ $totalPushed  ⚖️ $totalConflicts',
                      style: TextStyle(fontSize: 11),
                    ),
                ],
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
        }
      }

      ref.invalidate(smartSyncStatusProvider);
    } catch (e) {
      debugPrint('❌ فشل رفع التغييرات: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'تعذر رفع التغييرات. تحقق من الاتصال وبيانات الدخول',
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
            action: SnackBarAction(
              label: 'إعادة',
              textColor: Colors.white,
              onPressed: () => _uploadChanges(context),
            ),
          ),
        );
      }
    } finally {
      _uploadAnimationController.stop();
      _uploadAnimationController.reset();
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  /// حل التعارضات بين البيانات المحلية والبعيدة
  /// 
  /// تُستخدم بعد Pull لحل أي تعارضات تم اكتشافها
  /// الاستراتيجية: الأحدث يفوز (newerWins)
  Future<int> _resolveConflicts() async {
    int resolvedCount = 0;
    try {
      final db = ref.read(databaseProvider);
      final outboxDao = OutboxDao(db);
      
      // جلب التعارضات غير المحلولة من Outbox
      final conflicts = await outboxDao.getConflicts();
      
      if (conflicts.isEmpty) return 0;
      
      // إنشاء resolver باستراتيجية "الأحدث يفوز"
      final resolver = ConflictResolver(
        deviceId: await _getDeviceId(),
        strategy: ConflictStrategy.newerWins,
      );
      
      for (final conflict in conflicts) {
        try {
          final localData = conflict.localPayload;
          final remoteData = conflict.remotePayload;
          
          // تحويل البيانات إلى صيغة مناسبة للـ resolver
          final localMap = <String, Map<String, dynamic>>{
            conflict.targetTable: {conflict.uuid: localData},
          };
          final remoteMap = <String, Map<String, dynamic>>{
            conflict.targetTable: {conflict.uuid: remoteData},
          };
          
          // كشف وحل التعارض
          final dataConflicts = await resolver.detectConflicts(localMap, remoteMap);
          
          if (dataConflicts.isNotEmpty) {
            final resolved = await resolver.resolveConflicts(dataConflicts);
            
            // تطبيق الحل: تحديث السجل الفائز في قاعدة البيانات
            final winnerData = resolved[conflict.targetTable]?[conflict.uuid];
            if (winnerData != null) {
              await outboxDao.resolveConflict(
                conflict.id,
                winnerData,
                resolution: 'newer_wins',
              );
              resolvedCount++;
            }
          } else {
            // لا يوجد تعارض حقيقي، حله كـ "محلّل تلقائياً"
            await outboxDao.resolveConflict(
              conflict.id,
              localData,
              resolution: 'auto_no_conflict',
            );
          }
        } catch (e) {
          debugPrint('❌ خطأ في حل تعارض ${conflict.uuid}: $e');
        }
      }
      
      debugPrint('✅ تم حل $resolvedCount تعارض');
      return resolvedCount;
    } catch (e) {
      debugPrint('❌ خطأ في حل التعارضات: $e');
      return 0;
    }
  }
  
  /// الحصول على معرف الجهاز
  Future<String> _getDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var deviceId = prefs.getString('device_id');
      if (deviceId == null) {
        deviceId = 'device_${DateTime.now().millisecondsSinceEpoch}';
        await prefs.setString('device_id', deviceId);
      }
      return deviceId;
    } catch (e) {
      return 'unknown_device';
    }
  }

  String _formatLastUploadTime(DateTime? lastUpload) {
    if (lastUpload == null) return '';

    final now = DateTime.now();
    final difference = now.difference(lastUpload);

    if (difference.inSeconds < 60) {
      return 'رُفع منذ ${difference.inSeconds} ثانية';
    } else if (difference.inMinutes < 60) {
      return 'رُفع منذ ${difference.inMinutes} دقيقة';
    } else if (difference.inHours < 24) {
      return 'رُفع منذ ${difference.inHours} ساعة';
    } else {
      return 'رُفع منذ ${difference.inDays} يوم';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isGoogleDriveSignedIn = ref.watch(
      smartSyncGoogleDriveSignInStatusProvider,
    );
    final hasChanges = _pendingChangesCount > 0;

    Color buttonColor;
    IconData buttonIcon;
    String buttonText;
    String tooltipMessage;

    if (_isUploading) {
      buttonColor = Colors.blue;
      buttonIcon = Icons.cloud_upload;
      buttonText = 'جاري الرفع...';
      tooltipMessage = 'جاري رفع التغييرات إلى السحابة';
    } else if (!isGoogleDriveSignedIn && !_appwriteEnabled) {
      buttonColor = hasChanges ? Colors.orange : Colors.grey;
      buttonIcon = Icons.cloud_off;
      buttonText = hasChanges ? 'مطلوب دخول' : 'غير متصل';
      tooltipMessage = 'يجب تسجيل الدخول للمزامنة';
    } else if (hasChanges) {
      buttonColor = Colors.purple;
      buttonIcon = Icons.cloud_upload;
      buttonText = 'مزامنة التغييرات';
      tooltipMessage = 'اضغط لمزامنة $_pendingChangesCount تغيير إلى السحابة';
    } else if (!isGoogleDriveSignedIn && _appwriteEnabled) {
      buttonColor = Colors.blueGrey;
      buttonIcon = Icons.cloud_sync;
      buttonText = 'مزامنة Appwrite';
      tooltipMessage = 'المزامنة ستتم عبر Appwrite';
    } else {
      buttonColor = Colors.green;
      buttonIcon = Icons.cloud_done;
      buttonText = 'محدّث';
      tooltipMessage = 'جميع التغييرات مرفوعة - لا توجد تغييرات معلقة';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: tooltipMessage,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [buttonColor.withOpacity(0.85), buttonColor],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: buttonColor.withOpacity(
                        hasChanges || !isGoogleDriveSignedIn ? 0.4 : 0.2,
                      ),
                      blurRadius: hasChanges || !isGoogleDriveSignedIn ? 8 : 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: _isUploading
                        ? null
                        : () {
                            if (!isGoogleDriveSignedIn && !_appwriteEnabled) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const GoogleDriveBackupScreen(),
                                ),
                              );
                              return;
                            }
                            _uploadChanges(context);
                          },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_isUploading)
                            RotationTransition(
                              turns: _uploadAnimationController,
                              child: Icon(
                                buttonIcon,
                                size: 18,
                                color: Colors.white,
                              ),
                            )
                          else
                            Icon(buttonIcon, size: 18, color: Colors.white),
                          const SizedBox(width: 8),
                          Text(
                            buttonText,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (hasChanges && !_isUploading)
                Positioned(
                  top: -6,
                  right: -6,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withOpacity(0.5),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 22,
                      minHeight: 22,
                    ),
                    child: Center(
                      child: Text(
                        _pendingChangesCount > 99
                            ? '99+'
                            : '$_pendingChangesCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _isUploading
                ? Colors.blue.shade50
                : hasChanges
                ? Colors.purple.shade50
                : Colors.green.shade50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _isUploading
                  ? Colors.blue.shade200
                  : hasChanges
                  ? Colors.purple.shade200
                  : Colors.green.shade200,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                hasChanges
                    ? Icons.pending_actions
                    : (_isUploading ? Icons.sync : Icons.check_circle),
                size: 14,
                color: _isUploading
                    ? Colors.blue
                    : hasChanges
                    ? Colors.purple
                    : Colors.green,
              ),
              const SizedBox(width: 5),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    hasChanges
                        ? '$_pendingChangesCount تغيير معلق'
                        : (_isUploading ? 'جاري الرفع...' : 'لا توجد تغييرات'),
                    style: TextStyle(
                      fontSize: 11,
                      color: _isUploading
                          ? Colors.blue.shade900
                          : hasChanges
                          ? Colors.purple.shade900
                          : Colors.green.shade900,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (!_isUploading)
                    Consumer(
                      builder: (context, ref, _) {
                        final isGoogleDriveSignedIn = ref.watch(
                          smartSyncGoogleDriveSignInStatusProvider,
                        );

                        if (!hasChanges && _lastUploadTime != null) {
                          return Text(
                            _formatLastUploadTime(_lastUploadTime),
                            style: TextStyle(
                              fontSize: 8,
                              color: Colors.green.shade600,
                            ),
                          );
                        }

                        return Text(
                          isGoogleDriveSignedIn ? 'Google Drive' : 'غير متصل',
                          style: TextStyle(
                            fontSize: 8,
                            color: isGoogleDriveSignedIn
                                ? Colors.purple.shade600
                                : Colors.grey.shade600,
                          ),
                        );
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
