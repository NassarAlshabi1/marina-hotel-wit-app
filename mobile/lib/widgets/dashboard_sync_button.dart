import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/appwrite_providers.dart';
import '../providers/repository_providers.dart';
import '../services/daos/outbox_dao.dart';
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

    _pendingChangesTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && !_isUploading) {
        _loadPendingChangesCount();
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
    return prefs.getBool('appwrite_sync_enabled') ?? true;
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
    setState(() => _isUploading = true);

    try {
      final smartSyncManager = ref.read(smartSyncManagerProvider);
      final appwriteSyncManager = ref.read(appwriteSyncManagerProvider);

      final smartEnabled = await smartSyncManager.isEnabled();
      final isGoogleDriveSignedIn =
          ref.read(smartSyncGoogleDriveSignInStatusProvider);
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
                          'ℹ️ المزامنة معطلة - يرجى تفعيلها من الإعدادات')),
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.cloud_off, color: Colors.white),
                  SizedBox(width: 8),
                  Expanded(
                      child:
                          Text('⚠️ يرجى تسجيل الدخول إلى Google Drive أولاً')),
                ],
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
              action: SnackBarAction(
                label: 'تسجيل الدخول',
                textColor: Colors.white,
                onPressed: () {
                  // التوجه إلى شاشة Google Drive مباشرة
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const GoogleDriveBackupScreen()),
                  );
                },
              ),
            ),
          );
        }
        return;
      }

      final targets = <String>[];
      if (smartEnabled && isGoogleDriveSignedIn) targets.add('Google Drive');
      if (appwriteEnabled) targets.add('Appwrite');

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
                      '📤 رفع $_pendingChangesCount تغيير إلى $targetText...'),
                ),
              ],
            ),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 3),
          ),
        );
      }

      final futures = <Future<Object?>>[];
      final results = <String, bool>{};

      if (smartEnabled && isGoogleDriveSignedIn) {
        try {
          final result = await smartSyncManager.pushLocalChanges();
          results['Google Drive'] = result;
        } catch (e) {
          results['Google Drive'] = false;
          debugPrint('❌ خطأ في رفع البيانات إلى Google Drive: $e');
        }
      }

      if (appwriteEnabled) {
        try {
          final result = await appwriteSyncManager.pushLocalChanges();
          results['Appwrite'] = result;
        } catch (e) {
          results['Appwrite'] = false;
          debugPrint('❌ خطأ في رفع البيانات إلى Appwrite: $e');
        }
      }

      setState(() {
        _lastUploadTime = DateTime.now();
      });

      await _loadPendingChangesCount();

      final successTargets =
          results.entries.where((e) => e.value).map((e) => e.key).toList();
      final failedTargets =
          results.entries.where((e) => !e.value).map((e) => e.key).toList();

      if (mounted) {
        if (failedTargets.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.cloud_done, color: Colors.white),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        '✅ تم رفع التغييرات إلى ${successTargets.join(' + ')}'),
                  ),
                ],
              ),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
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
                        '❌ فشل رفع التغييرات إلى ${failedTargets.join(' + ')}'),
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
                    children: [
                      Icon(Icons.warning, color: Colors.white),
                      SizedBox(width: 8),
                      Text('⚠️ نجح جزئياً'),
                    ],
                  ),
                  SizedBox(height: 4),
                  Text('✅ نجح: ${successTargets.join(', ')}',
                      style: TextStyle(fontSize: 12)),
                  Text('❌ فشل: ${failedTargets.join(', ')}',
                      style: TextStyle(fontSize: 12)),
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white),
                SizedBox(width: 8),
                Expanded(child: Text('❌ فشل رفع التغييرات: $e')),
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
    final isGoogleDriveSignedIn =
        ref.watch(smartSyncGoogleDriveSignInStatusProvider);
    final hasChanges = _pendingChangesCount > 0;
    // تمكين الزر إذا كان هناك تغييرات أو إذا كان غير متصل (للسماح بالضغط لتسجيل الدخول)
    final isEnabled = hasChanges || _isUploading || !isGoogleDriveSignedIn;

    Color buttonColor;
    IconData buttonIcon;
    String buttonText;
    String tooltipMessage;

    if (_isUploading) {
      buttonColor = Colors.blue;
      buttonIcon = Icons.cloud_upload;
      buttonText = 'جاري الرفع...';
      tooltipMessage = 'جاري رفع التغييرات إلى السحابة';
    } else if (!isGoogleDriveSignedIn) {
      buttonColor = hasChanges ? Colors.orange : Colors.grey;
      buttonIcon = Icons.cloud_off;
      buttonText = hasChanges ? 'مطلوب دخول' : 'غير متصل';
      tooltipMessage = 'يجب تسجيل الدخول للمزامنة';
    } else if (hasChanges) {
      buttonColor = Colors.purple;
      buttonIcon = Icons.cloud_upload;
      buttonText = 'رفع التغييرات';
      tooltipMessage = 'اضغط لرفع $_pendingChangesCount تغيير إلى السحابة';
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
                    colors: [
                      buttonColor.withOpacity(0.85),
                      buttonColor,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: buttonColor.withOpacity(
                          hasChanges || !isGoogleDriveSignedIn ? 0.4 : 0.2),
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
                            if (!isGoogleDriveSignedIn) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        const GoogleDriveBackupScreen()),
                              );
                            } else if (hasChanges) {
                              _uploadChanges(context);
                            }
                          },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
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
                            Icon(
                              buttonIcon,
                              size: 18,
                              color: Colors.white,
                            ),
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
                        final isGoogleDriveSignedIn =
                            ref.watch(smartSyncGoogleDriveSignInStatusProvider);

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
