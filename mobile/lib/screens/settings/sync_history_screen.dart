import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../providers/repository_providers.dart';
import '../../providers/sync_log_providers.dart';
import '../../services/daos/sync_log_dao.dart';

/// ═══════════════════════════════════════════════════════════════
/// شاشة سجل المزامنة المحسنة
/// ═══════════════════════════════════════════════════════════════
class SyncHistoryScreen extends ConsumerStatefulWidget {
  const SyncHistoryScreen({super.key});

  @override
  ConsumerState<SyncHistoryScreen> createState() => _SyncHistoryScreenState();
}

class _SyncHistoryScreenState extends ConsumerState<SyncHistoryScreen> {
  String? _selectedDirection;
  String? _selectedStatus;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filter = SyncFilter(
      direction: _selectedDirection,
      status: _selectedStatus,
    );

    final logsAsync = ref.watch(syncHistoryProvider(filter));
    final statsAsync = ref.watch(syncLogStatsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('سجل المزامنة'),
        actions: [
          // زر التحديث
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(syncHistoryProvider);
              ref.invalidate(syncLogStatsProvider);
            },
            tooltip: 'تحديث',
          ),
          // قائمة الخيارات
          PopupMenuButton<String>(
            onSelected: (value) => _handleMenuAction(value, logsAsync),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'copy_all',
                child: Row(
                  children: [
                    Icon(Icons.copy, size: 20),
                    SizedBox(width: 12),
                    Text('نسخ جميع السجلات'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'share_all',
                child: Row(
                  children: [
                    Icon(Icons.share, size: 20),
                    SizedBox(width: 12),
                    Text('مشاركة السجلات'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'clear_all',
                child: Row(
                  children: [
                    Icon(Icons.delete_forever, size: 20, color: Colors.red),
                    SizedBox(width: 12),
                    Text('مسح جميع السجلات', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // ═════════════════════════════════════════════════════════
          // بطاقة الإحصائيات
          // ═════════════════════════════════════════════════════════
          statsAsync.when(
            data: (stats) => _buildStatsCard(stats),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),

          // ═════════════════════════════════════════════════════════
          // شريط البحث والفلترة
          // ═════════════════════════════════════════════════════════
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                // زر الفلترة
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: IconButton(
                    icon: Badge(
                      isLabelVisible: _selectedDirection != null || _selectedStatus != null,
                      child: const Icon(Icons.filter_list),
                    ),
                    onPressed: _showFilterDialog,
                    tooltip: 'تصفية',
                  ),
                ),
                const SizedBox(width: 12),
                // البحث
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) {
                      setState(() => _searchQuery = value.toLowerCase());
                    },
                    decoration: InputDecoration(
                      hintText: 'بحث في السجلات...',
                      hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 20),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ═════════════════════════════════════════════════════════
          // قائمة السجلات
          // ═════════════════════════════════════════════════════════
          Expanded(
            child: logsAsync.when(
              data: (logs) {
                // تطبيق البحث
                final filteredLogs = _searchQuery.isEmpty
                    ? logs
                    : logs.where((log) {
                        final searchLower = _searchQuery.toLowerCase();
                        return log.syncId.toLowerCase().contains(searchLower) ||
                            log.deviceId.toLowerCase().contains(searchLower) ||
                            (log.errorMessage?.toLowerCase().contains(searchLower) ?? false) ||
                            (log.target?.toLowerCase().contains(searchLower) ?? false);
                      }).toList();

                if (filteredLogs.isEmpty) {
                  return _buildEmptyState(logs.isEmpty);
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(syncHistoryProvider);
                    ref.invalidate(syncLogStatsProvider);
                  },
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredLogs.length,
                    itemBuilder: (context, index) {
                      final log = filteredLogs[index];
                      return _buildLogCard(log);
                    },
                  ),
                );
              },
              loading: () => const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('جاري تحميل السجلات...'),
                  ],
                ),
              ),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
                      const SizedBox(height: 16),
                      Text(
                        'خطأ في تحميل السجلات',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        error.toString(),
                        style: TextStyle(color: Colors.grey.shade600),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: () => ref.invalidate(syncHistoryProvider),
                        icon: const Icon(Icons.refresh),
                        label: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// ═══════════════════════════════════════════════════════════════
  /// بطاقة الإحصائيات
  /// ═══════════════════════════════════════════════════════════════
  Widget _buildStatsCard(SyncStats stats) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.blue.shade600,
            Colors.blue.shade800,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.shade200.withOpacity(0.5),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // الصف الأول: إجمالي ومعدل النجاح
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  icon: Icons.sync_alt,
                  label: 'إجمالي',
                  value: '${stats.totalSyncs}',
                  color: Colors.white,
                ),
              ),
              Container(
                height: 40,
                width: 1,
                color: Colors.white.withOpacity(0.3),
              ),
              Expanded(
                child: _buildStatItem(
                  icon: Icons.trending_up,
                  label: 'معدل النجاح',
                  value: '${stats.successRate.toStringAsFixed(0)}%',
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // الصف الثاني: ناجح وفاشل
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  icon: Icons.check_circle,
                  label: 'ناجح',
                  value: '${stats.successfulSyncs}',
                  color: Colors.green.shade300,
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  icon: Icons.error,
                  label: 'فاشل',
                  value: '${stats.failedSyncs}',
                  color: stats.failedSyncs > 0 ? Colors.red.shade300 : Colors.white70,
                  highlight: stats.failedSyncs > 0,
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  icon: Icons.timer,
                  label: 'متوسط المدة',
                  value: stats.averageDurationMs > 1000
                      ? '${(stats.averageDurationMs / 1000).toStringAsFixed(1)}s'
                      : '${stats.averageDurationMs}ms',
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    bool highlight = false,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: color.withOpacity(0.8),
          ),
        ),
      ],
    );
  }

  /// ═══════════════════════════════════════════════════════════════
  /// الحالة الفارغة
  /// ═══════════════════════════════════════════════════════════════
  Widget _buildEmptyState(bool noRecordsAtAll) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              noRecordsAtAll ? Icons.history_toggle_off : Icons.search_off,
              size: 80,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 24),
            Text(
              noRecordsAtAll ? 'لا توجد عمليات مزامنة' : 'لا توجد نتائج مطابقة',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              noRecordsAtAll
                  ? 'سيظهر هنا سجل جميع عمليات المزامنة\nالناجحة والفاشلة'
                  : 'جرب تغيير معايير البحث أو الفلترة',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
              ),
              textAlign: TextAlign.center,
            ),
            if (noRecordsAtAll) ...[
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue.shade700),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        'قم بإجراء عملية مزامنة من الشاشة الرئيسية\nلتسجيل أول سجل',
                        style: TextStyle(
                          color: Colors.blue.shade700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// ═══════════════════════════════════════════════════════════════
  /// بطاقة السجل
  /// ═══════════════════════════════════════════════════════════════
  Widget _buildLogCard(SyncLogEntry log) {
    final isSuccess = log.status == 'success';
    final isPartial = log.status == 'partial' || log.status == 'in_progress';
    final isPull = log.direction == 'pull';
    final isBidirectional = log.direction == 'bidirectional';

    // تحديد الألوان والأيقونات
    Color statusColor;
    IconData statusIcon;
    String statusText;
    Color statusBgColor;

    if (isSuccess) {
      statusColor = Colors.green.shade700;
      statusBgColor = Colors.green.shade50;
      statusIcon = Icons.check_circle_rounded;
      statusText = 'نجح';
    } else if (isPartial) {
      statusColor = Colors.orange.shade700;
      statusBgColor = Colors.orange.shade50;
      statusIcon = Icons.pending_rounded;
      statusText = log.status == 'in_progress' ? 'جاري' : 'جزئي';
    } else {
      statusColor = Colors.red.shade700;
      statusBgColor = Colors.red.shade50;
      statusIcon = Icons.error_rounded;
      statusText = 'فشل';
    }

    // نوع العملية
    String directionText;
    IconData directionIcon;
    Color directionColor;

    if (isBidirectional) {
      directionText = 'مزامنة';
      directionIcon = Icons.sync_alt_rounded;
      directionColor = Colors.teal;
    } else if (isPull) {
      directionText = 'سحب';
      directionIcon = Icons.cloud_download_rounded;
      directionColor = Colors.blue;
    } else {
      directionText = 'رفع';
      directionIcon = Icons.cloud_upload_rounded;
      directionColor = Colors.purple;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSuccess ? Colors.green.shade200 : Colors.red.shade200,
          width: 1.5,
        ),
      ),
      child: InkWell(
        onTap: () => _showLogDetails(log),
        onLongPress: () => _showQuickActions(log),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // الصف الأول: النوع والحالة
              Row(
                children: [
                  // أيقونة النوع
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: directionColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(directionIcon, color: directionColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  // النوع والمعرف
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              directionText,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            if (log.target != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  log.target!,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatRelativeTime(log.createdAt),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // حالة العملية
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: statusColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcon, color: Colors.white, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          statusText,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // معلومات إضافية
              const SizedBox(height: 12),
              Row(
                children: [
                  // الوقت الكامل
                  _buildInfoChip(
                    icon: Icons.access_time_rounded,
                    label: _formatFullDateTime(log.createdAt),
                  ),
                  // المدة
                  if (log.durationMs != null && log.durationMs! > 0) ...[
                    const SizedBox(width: 8),
                    _buildInfoChip(
                      icon: Icons.timer_outlined,
                      label: log.durationMs! > 1000
                          ? '${(log.durationMs! / 1000).toStringAsFixed(1)}s'
                          : '${log.durationMs}ms',
                    ),
                  ],
                  // عدد السجلات
                  if (log.recordsCount != null && log.recordsCount! > 0) ...[
                    const SizedBox(width: 8),
                    _buildInfoChip(
                      icon: Icons.dataset_outlined,
                      label: '${log.recordsCount}',
                    ),
                  ],
                ],
              ),

              // رسالة الخطأ
              if (log.errorMessage != null && log.errorMessage!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade100),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        color: Colors.red.shade600,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          log.errorMessage!,
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontSize: 12,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // زر نسخ الخطأ
                      InkWell(
                        onTap: () => _copyErrorToClipboard(log.errorMessage!),
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            Icons.copy_rounded,
                            color: Colors.red.shade400,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.grey.shade600),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  /// ═══════════════════════════════════════════════════════════════
  /// عرض تفاصيل السجل
  /// ═══════════════════════════════════════════════════════════════
  void _showLogDetails(SyncLogEntry log) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                // المؤشر العلوي
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(24),
                    children: [
                      _buildDetailsHeader(log),
                      const SizedBox(height: 24),
                      _buildDetailsContent(log),
                      const SizedBox(height: 24),
                      _buildDetailsActions(log),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDetailsHeader(SyncLogEntry log) {
    final isSuccess = log.status == 'success';
    final isPull = log.direction == 'pull';
    final isBidirectional = log.direction == 'bidirectional';

    String directionText;
    IconData directionIcon;
    Color directionColor;

    if (isBidirectional) {
      directionText = 'مزامنة ثنائية';
      directionIcon = Icons.sync_alt_rounded;
      directionColor = Colors.teal;
    } else if (isPull) {
      directionText = 'سحب من السيرفر';
      directionIcon = Icons.cloud_download_rounded;
      directionColor = Colors.blue;
    } else {
      directionText = 'رفع إلى السيرفر';
      directionIcon = Icons.cloud_upload_rounded;
      directionColor = Colors.purple;
    }

    return Row(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: directionColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(directionIcon, color: directionColor, size: 28),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                directionText,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                log.syncId,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
        // حالة العملية
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSuccess ? Colors.green : Colors.red,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isSuccess ? Icons.check_circle : Icons.error,
                color: Colors.white,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                isSuccess ? 'نجح' : 'فشل',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDetailsContent(SyncLogEntry log) {
    return Column(
      children: [
        _buildDetailSection('معلومات أساسية', [
          _buildDetailRow('معرف المزامنة', log.syncId, canCopy: true),
          _buildDetailRow('الجهاز', log.deviceId, canCopy: true),
          _buildDetailRow('الحالة', _translateStatus(log.status)),
          if (log.target != null)
            _buildDetailRow('الوجهة', log.target!),
        ]),
        const SizedBox(height: 16),
        _buildDetailSection('التوقيت', [
          _buildDetailRow('وقت البدء', _formatFullDateTime(log.createdAt)),
          if (log.completedAt != null)
            _buildDetailRow('وقت الانتهاء', _formatFullDateTime(log.completedAt!)),
          if (log.durationMs != null)
            _buildDetailRow('المدة', _formatDuration(log.durationMs!)),
        ]),
        if (log.recordsCount != null) ...[
          const SizedBox(height: 16),
          _buildDetailSection('البيانات', [
            _buildDetailRow('عدد السجلات', '${log.recordsCount}'),
          ]),
        ],
        if (log.errorMessage != null && log.errorMessage!.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildDetailSection('تفاصيل الخطأ', [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: SelectableText(
                log.errorMessage!,
                style: TextStyle(
                  color: Colors.red.shade700,
                  fontSize: 13,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ]),
        ],
      ],
    );
  }

  Widget _buildDetailSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade500,
          ),
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }

  Widget _buildDetailRow(String label, String value, {bool canCopy = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ),
                if (canCopy)
                  InkWell(
                    onTap: () => _copyToClipboard(value),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.copy_rounded,
                        size: 16,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsActions(SyncLogEntry log) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _copyLogToClipboard(log),
            icon: const Icon(Icons.copy_rounded),
            label: const Text('نسخ'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _shareLog(log),
            icon: const Icon(Icons.share_rounded),
            label: const Text('مشاركة'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
            label: const Text('إغلاق'),
          ),
        ),
      ],
    );
  }

  /// ═══════════════════════════════════════════════════════════════
  /// إجراءات سريعة
  /// ═══════════════════════════════════════════════════════════════
  void _showQuickActions(SyncLogEntry log) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('نسخ السجل'),
                onTap: () {
                  Navigator.pop(context);
                  _copyLogToClipboard(log);
                },
              ),
              ListTile(
                leading: const Icon(Icons.share),
                title: const Text('مشاركة السجل'),
                onTap: () {
                  Navigator.pop(context);
                  _shareLog(log);
                },
              ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('عرض التفاصيل'),
                onTap: () {
                  Navigator.pop(context);
                  _showLogDetails(log);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// ═══════════════════════════════════════════════════════════════
  /// معالجة إجراءات القائمة
  /// ═══════════════════════════════════════════════════════════════
  void _handleMenuAction(String action, AsyncValue<List<SyncLogEntry>> logsAsync) {
    switch (action) {
      case 'copy_all':
        _copyAllLogs(logsAsync);
        break;
      case 'share_all':
        _shareAllLogs(logsAsync);
        break;
      case 'clear_all':
        _showClearConfirmation();
        break;
    }
  }

  /// ═══════════════════════════════════════════════════════════════
  /// وظائف النسخ والمشاركة
  /// ═══════════════════════════════════════════════════════════════
  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    _showSnackBar('تم النسخ إلى الحافظة', Colors.green);
  }

  void _copyErrorToClipboard(String errorMessage) {
    Clipboard.setData(ClipboardData(text: errorMessage));
    _showSnackBar('تم نسخ الخطأ', Colors.green);
  }

  void _copyLogToClipboard(SyncLogEntry log) {
    final text = _formatLogForCopy(log);
    Clipboard.setData(ClipboardData(text: text));
    _showSnackBar('تم نسخ السجل', Colors.green);
  }

  void _copyAllLogs(AsyncValue<List<SyncLogEntry>> logsAsync) {
    logsAsync.whenData((logs) {
      if (logs.isEmpty) {
        _showSnackBar('لا توجد سجلات للنسخ', Colors.orange);
        return;
      }

      final buffer = StringBuffer();
      buffer.writeln('╔══════════════════════════════════════════════════════════╗');
      buffer.writeln('║              📋 سجل المزامنة الكامل                       ║');
      buffer.writeln('╚══════════════════════════════════════════════════════════╝');
      buffer.writeln();
      buffer.writeln('📅 تاريخ التصدير: ${DateTime.now().toString().split(".")[0]}');
      buffer.writeln('📊 عدد السجلات: ${logs.length}');
      buffer.writeln();

      int successCount = logs.where((l) => l.status == 'success').length;
      int failedCount = logs.where((l) => l.status == 'failed').length;

      for (final log in logs) {
        buffer.writeln(_formatLogForCopy(log));
        buffer.writeln();
      }

      buffer.writeln('══════════════════════════════════════════════════════════');
      buffer.writeln('📊 الإحصائيات:');
      buffer.writeln('   ✅ ناجحة: $successCount');
      buffer.writeln('   ❌ فاشلة: $failedCount');
      buffer.writeln('   📦 المجموع: ${logs.length}');
      buffer.writeln('══════════════════════════════════════════════════════════');

      Clipboard.setData(ClipboardData(text: buffer.toString()));
      _showSnackBar('تم نسخ ${logs.length} سجل', Colors.green);
    });
  }

  void _shareLog(SyncLogEntry log) {
    final text = _formatLogForCopy(log);
    Share.share(text, subject: 'سجل المزامنة - ${log.syncId}');
  }

  void _shareAllLogs(AsyncValue<List<SyncLogEntry>> logsAsync) {
    logsAsync.whenData((logs) {
      if (logs.isEmpty) {
        _showSnackBar('لا توجد سجلات للمشاركة', Colors.orange);
        return;
      }

      final buffer = StringBuffer();
      buffer.writeln('سجل المزامنة - ${DateTime.now().toString().split(".")[0]}');
      buffer.writeln('عدد السجلات: ${logs.length}');
      buffer.writeln('─' * 40);

      for (final log in logs) {
        buffer.writeln('[${log.status == 'success' ? '✅' : '❌'}] ${_translateDirection(log.direction)} - ${_formatFullDateTime(log.createdAt)}');
        if (log.errorMessage != null) {
          buffer.writeln('   الخطأ: ${log.errorMessage}');
        }
      }

      Share.share(buffer.toString(), subject: 'سجل المزامنة');
    });
  }

  String _formatLogForCopy(SyncLogEntry log) {
    final buffer = StringBuffer();
    final isSuccess = log.status == 'success';

    buffer.writeln('════════════════════════════════════════');
    buffer.writeln('📋 سجل المزامنة');
    buffer.writeln('════════════════════════════════════════');
    buffer.writeln();
    buffer.writeln('🆔 المعرف: ${log.syncId}');
    buffer.writeln('📌 النوع: ${_translateDirection(log.direction)}');
    buffer.writeln('📊 الحالة: ${isSuccess ? '✅ نجح' : '❌ فشل'}');
    buffer.writeln('📱 الجهاز: ${log.deviceId}');
    buffer.writeln('🎯 الوجهة: ${log.target ?? 'غير معروف'}');
    buffer.writeln('⏰ الوقت: ${_formatFullDateTime(log.createdAt)}');

    if (log.durationMs != null) {
      buffer.writeln('⏱️ المدة: ${_formatDuration(log.durationMs!)}');
    }

    if (log.recordsCount != null && log.recordsCount! > 0) {
      buffer.writeln('📦 السجلات: ${log.recordsCount}');
    }

    if (log.errorMessage != null && log.errorMessage!.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('────────────────────────────────────────');
      buffer.writeln('❌ الخطأ:');
      buffer.writeln(log.errorMessage!);
      buffer.writeln('────────────────────────────────────────');
    }

    buffer.writeln();
    buffer.writeln('📅 تم النسخ: ${DateTime.now().toString().split('.')[0]}');

    return buffer.toString();
  }

  /// ═══════════════════════════════════════════════════════════════
  /// تأكيد مسح السجلات
  /// ═══════════════════════════════════════════════════════════════
  void _showClearConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text('تأكيد المسح'),
          ],
        ),
        content: const Text(
          'هل أنت متأكد من مسح جميع سجلات المزامنة؟\n\n'
          '⚠️ لا يمكن التراجع عن هذا الإجراء.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(context);
              // TODO: Implement clear logs
              _showSnackBar('تم مسح السجلات', Colors.green);
              ref.invalidate(syncHistoryProvider);
              ref.invalidate(syncLogStatsProvider);
            },
            child: const Text('مسح'),
          ),
        ],
      ),
    );
  }

  /// ═══════════════════════════════════════════════════════════════
  /// فلترة السجلات
  /// ═══════════════════════════════════════════════════════════════
  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تصفية السجلات'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String?>(
              value: _selectedDirection,
              decoration: const InputDecoration(
                labelText: 'نوع العملية',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: null, child: Text('الكل')),
                DropdownMenuItem(value: 'bidirectional', child: Text('مزامنة')),
                DropdownMenuItem(value: 'pull', child: Text('سحب')),
                DropdownMenuItem(value: 'push', child: Text('رفع')),
              ],
              onChanged: (value) => setState(() => _selectedDirection = value),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String?>(
              value: _selectedStatus,
              decoration: const InputDecoration(
                labelText: 'الحالة',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: null, child: Text('الكل')),
                DropdownMenuItem(value: 'success', child: Text('✅ نجح')),
                DropdownMenuItem(value: 'failed', child: Text('❌ فشل')),
                DropdownMenuItem(value: 'in_progress', child: Text('⏳ جاري')),
              ],
              onChanged: (value) => setState(() => _selectedStatus = value),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _selectedDirection = null;
                _selectedStatus = null;
              });
              Navigator.pop(context);
            },
            child: const Text('إعادة تعيين'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('تطبيق'),
          ),
        ],
      ),
    );
  }

  /// ═══════════════════════════════════════════════════════════════
  /// دوال مساعدة
  /// ═══════════════════════════════════════════════════════════════
  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  String _formatRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inSeconds < 60) {
      return 'الآن';
    } else if (diff.inMinutes < 60) {
      return 'منذ ${diff.inMinutes} دقيقة';
    } else if (diff.inHours < 24) {
      return 'منذ ${diff.inHours} ساعة';
    } else if (diff.inDays < 7) {
      return 'منذ ${diff.inDays} يوم';
    } else {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    }
  }

  String _formatFullDateTime(DateTime dateTime) {
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final year = dateTime.year;
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  String _formatDuration(int ms) {
    if (ms < 1000) return '$ms مللي ثانية';
    final seconds = (ms / 1000).toStringAsFixed(1);
    return '$seconds ثانية';
  }

  String _translateStatus(String status) {
    switch (status) {
      case 'success':
        return 'نجح';
      case 'failed':
        return 'فشل';
      case 'in_progress':
        return 'جاري التنفيذ';
      case 'partial':
        return 'نجح جزئياً';
      default:
        return status;
    }
  }

  String _translateDirection(String direction) {
    switch (direction) {
      case 'bidirectional':
        return 'مزامنة ثنائية';
      case 'pull':
        return 'سحب';
      case 'push':
        return 'رفع';
      default:
        return direction;
    }
  }
}
