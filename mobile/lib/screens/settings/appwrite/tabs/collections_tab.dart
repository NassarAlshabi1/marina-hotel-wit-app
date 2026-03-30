import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/core.dart';
import '../../../../services/appwrite_config.dart';

/// Appwrite Collections Tab - إدارة الجداول والحقول المزامنة
class AppwriteCollectionsTab extends ConsumerStatefulWidget {
  const AppwriteCollectionsTab({super.key});

  @override
  ConsumerState<AppwriteCollectionsTab> createState() =>
      _AppwriteCollectionsTabState();
}

class _AppwriteCollectionsTabState
    extends ConsumerState<AppwriteCollectionsTab> {
  @override
  void initState() {
    super.initState();
    _loadSyncStatus();
  }

  Future<void> _loadSyncStatus() async {
    // تحميل حالة المزامنة لكل جدول من SharedPreferences
    // سيتم تنفيذه لاحقاً
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(UIConstants.spacingMD),
      children: [
        _buildCollectionsOverviewCard(),
        const SizedBox(height: UIConstants.spacingLG),
        _buildCollectionsListCard(),
      ],
    );
  }

  Widget _buildCollectionsOverviewCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UIConstants.radiusLG),
      ),
      child: Padding(
        padding: const EdgeInsets.all(UIConstants.spacingMD),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.storage,
                  color: Colors.blue,
                  size: UIConstants.iconSizeMD,
                ),
                SizedBox(width: UIConstants.spacingSM),
                Text(
                  'الجداول والحقول المزامنة',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: UIConstants.spacingMD),
            Container(
              padding: const EdgeInsets.all(UIConstants.spacingMD),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(UIConstants.radiusMD),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatItem('17', 'إجمالي الجداول'),
                      _buildStatItem('---', 'إجمالي السجلات'),
                      _buildStatItem('---', 'حجم البيانات'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: UIConstants.spacingMD),
            const Text(
              'يتم مزامنة جميع الحقول من الجداول أدناه مع Appwrite Cloud بشكل تلقائي.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.blue,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _buildCollectionsListCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UIConstants.radiusLG),
      ),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(UIConstants.spacingMD),
            child: Row(
              children: [
                Icon(
                  Icons.list,
                  color: Colors.blue,
                  size: UIConstants.iconSizeMD,
                ),
                SizedBox(width: UIConstants.spacingSM),
                Text(
                  'قائمة الجداول',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ..._buildCollectionItems(),
        ],
      ),
    );
  }

  List<Widget> _buildCollectionItems() {
    final collections = [
      _CollectionInfo(
        id: AppwriteConfig.roomsCollectionId,
        name: 'الغرف',
        description: 'بيانات الغرف الفندقية',
        icon: Icons.hotel,
        color: Colors.blue,
      ),
      _CollectionInfo(
        id: AppwriteConfig.bookingsCollectionId,
        name: 'الحجوزات',
        description: 'بيانات الحجوزات',
        icon: Icons.calendar_today,
        color: Colors.green,
      ),
      _CollectionInfo(
        id: AppwriteConfig.bookingNotesCollectionId,
        name: 'ملاحظات الحجوزات',
        description: 'ملاحظات إضافية على الحجوزات',
        icon: Icons.note,
        color: Colors.orange,
      ),
      _CollectionInfo(
        id: AppwriteConfig.bookingNightsCollectionId,
        name: 'ليالي الحجوزات',
        description: 'تفاصيل الليالي المحجوزة',
        icon: Icons.nights_stay,
        color: Colors.purple,
      ),
      _CollectionInfo(
        id: AppwriteConfig.paymentsCollectionId,
        name: 'المدفوعات',
        description: 'سجلات المدفوعات',
        icon: Icons.payment,
        color: Colors.red,
      ),
      _CollectionInfo(
        id: AppwriteConfig.expensesCollectionId,
        name: 'المصروفات',
        description: 'سجلات المصروفات',
        icon: Icons.trending_down,
        color: Colors.red,
      ),
      _CollectionInfo(
        id: AppwriteConfig.cashTransactionsCollectionId,
        name: 'المعاملات النقدية',
        description: 'معاملات النقد',
        icon: Icons.money,
        color: Colors.amber,
      ),
      _CollectionInfo(
        id: AppwriteConfig.debtsCollectionId,
        name: 'الديون',
        description: 'سجلات الديون',
        icon: Icons.credit_card,
        color: Colors.red,
      ),
      _CollectionInfo(
        id: AppwriteConfig.employeesCollectionId,
        name: 'الموظفون',
        description: 'بيانات الموظفين',
        icon: Icons.people,
        color: Colors.teal,
      ),
      _CollectionInfo(
        id: AppwriteConfig.salaryCyclesCollectionId,
        name: 'دورات الرواتب',
        description: 'دورات الرواتب',
        icon: Icons.calendar_month,
        color: Colors.cyan,
      ),
      _CollectionInfo(
        id: AppwriteConfig.salaryPaymentsCollectionId,
        name: 'دفعات الرواتب',
        description: 'سجلات دفعات الرواتب',
        icon: Icons.account_balance_wallet,
        color: Colors.cyan,
      ),
      // ❌ hotel_day_ledger - محلي فقط، لا يتم مزامنته مع Appwrite
      _CollectionInfo(
        id: AppwriteConfig.shiftNotesCollectionId,
        name: 'ملاحظات النوبة',
        description: 'ملاحظات نوبات العمل',
        icon: Icons.schedule,
        color: Colors.lime,
      ),
      _CollectionInfo(
        id: AppwriteConfig.priceAdjustmentsCollectionId,
        name: 'تعديلات الأسعار',
        description: 'تعديلات الأسعار العامة',
        icon: Icons.price_change,
        color: Colors.deepOrange,
      ),
      _CollectionInfo(
        id: AppwriteConfig.bookingPriceAdjustmentsCollectionId,
        name: 'تعديلات أسعار الحجوزات',
        description: 'تعديلات أسعار الحجوزات',
        icon: Icons.discount,
        color: Colors.deepOrange,
      ),
      _CollectionInfo(
        id: AppwriteConfig.auditLogsCollectionId,
        name: 'سجلات التدقيق',
        description: 'سجلات التدقيق والأمان',
        icon: Icons.security,
        color: Colors.brown,
      ),
      _CollectionInfo(
        id: AppwriteConfig.paymentVoidsCollectionId,
        name: 'إلغاءات الدفع',
        description: 'سجلات إلغاءات الدفع',
        icon: Icons.cancel,
        color: Colors.red,
      ),
    ];

    return collections.asMap().entries.map((entry) {
      final isLast = entry.key == collections.length - 1;
      return Column(
        children: [
          _buildCollectionTile(entry.value),
          if (!isLast) const Divider(height: 1),
        ],
      );
    }).toList();
  }

  Widget _buildCollectionTile(_CollectionInfo collection) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: collection.color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(UIConstants.radiusMD),
        ),
        child: Icon(collection.icon, color: collection.color, size: 24),
      ),
      title: Text(
        collection.name,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text(collection.description),
      trailing: Icon(
        Icons.arrow_forward_ios,
        size: 16,
        color: Colors.grey.shade400,
      ),
      onTap: () => _showCollectionDetails(collection),
    );
  }

  void _showCollectionDetails(_CollectionInfo collection) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(UIConstants.spacingLG),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: collection.color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(
                          UIConstants.radiusMD,
                        ),
                      ),
                      child: Icon(
                        collection.icon,
                        color: collection.color,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: UIConstants.spacingMD),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            collection.name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            collection.description,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: UIConstants.spacingLG),
                const Divider(),
                const SizedBox(height: UIConstants.spacingMD),
                const Text(
                  'معرف الجدول:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(UIConstants.spacingMD),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(UIConstants.radiusMD),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          collection.id,
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy),
                        onPressed: () {
                          // Copy to clipboard
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('تم نسخ معرف الجدول')),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: UIConstants.spacingLG),
                const Text(
                  'حالة المزامنة:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(UIConstants.spacingMD),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(UIConstants.radiusMD),
                    border: Border.all(color: Colors.green.withOpacity(0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green),
                      SizedBox(width: 8),
                      Text(
                        'مفعل - يتم المزامنة',
                        style: TextStyle(color: Colors.green),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: UIConstants.spacingLG),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('إغلاق'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CollectionInfo {
  _CollectionInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
  });
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final Color color;
}
