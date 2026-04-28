import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/core.dart';

/// File Management Tab - استيراد وتصدير البيانات
class FileManagementTab extends ConsumerWidget {
  const FileManagementTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(UIConstants.spacingMD),
      children: [
        // Import/Export Actions
        _buildImportExportCard(),

        const SizedBox(height: UIConstants.spacingLG),

        // File Types
        SectionHeader(
          title: 'أنواع الملفات المدعومة',
          icon: Icons.file_present,
        ),
        _buildFileTypesGrid(context),

        const SizedBox(height: UIConstants.spacingLG),

        // Recent Operations
        SectionHeader(title: 'العمليات الأخيرة', icon: Icons.history),
        _buildRecentOperationsList(),
      ],
    );
  }

  Widget _buildImportExportCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UIConstants.radiusLG),
      ),
      child: Padding(
        padding: const EdgeInsets.all(UIConstants.spacingMD),
        child: Column(
          children: [
            const Icon(Icons.import_export, size: 48, color: Colors.blue),
            const SizedBox(height: UIConstants.spacingMD),
            const Text(
              'استيراد وتصدير البيانات',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: UIConstants.spacingSM),
            Text(
              'انقل بياناتك بسهولة بين الأجهزة',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: UIConstants.spacingLG),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.file_upload),
                    label: const Text('استيراد'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.all(UIConstants.spacingMD),
                    ),
                  ),
                ),
                const SizedBox(width: UIConstants.spacingMD),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.file_download),
                    label: const Text('تصدير'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.all(UIConstants.spacingMD),
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

  Widget _buildFileTypesGrid(BuildContext context) {
    final fileTypes = [
      {'name': 'JSON', 'icon': Icons.code, 'color': Colors.orange},
      {'name': 'CSV', 'icon': Icons.table_chart, 'color': Colors.green},
      {'name': 'Excel', 'icon': Icons.table_view, 'color': Colors.teal},
      {'name': 'SQL', 'icon': Icons.storage, 'color': Colors.blue},
    ];

    final width = MediaQuery.sizeOf(context).width;
    final crossAxisCount = width < 360
        ? 1
        : width < 600
        ? 2
        : 3;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: UIConstants.spacingMD,
        crossAxisSpacing: UIConstants.spacingMD,
        childAspectRatio: 1.5,
      ),
      itemCount: fileTypes.length,
      itemBuilder: (context, index) {
        final fileType = fileTypes[index];
        return Card(
          child: InkWell(
            onTap: () {},
            borderRadius: BorderRadius.circular(UIConstants.radiusLG),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  fileType['icon'] as IconData,
                  size: UIConstants.iconSizeLG,
                  color: fileType['color'] as Color,
                ),
                const SizedBox(height: UIConstants.spacingSM),
                Text(
                  fileType['name'] as String,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRecentOperationsList() {
    final operations = [
      {
        'type': 'export',
        'format': 'JSON',
        'date': '2024-01-29T18:00:00',
        'status': 'success',
      },
      {
        'type': 'import',
        'format': 'CSV',
        'date': '2024-01-28T15:00:00',
        'status': 'success',
      },
      {
        'type': 'export',
        'format': 'Excel',
        'date': '2024-01-27T10:00:00',
        'status': 'failed',
      },
    ];

    if (operations.isEmpty) {
      return const EmptyStateWidget(
        message: 'لا توجد عمليات حديثة',
        icon: Icons.folder_open,
      );
    }

    return Column(
      children: operations.map((op) => _buildOperationItem(op)).toList(),
    );
  }

  Widget _buildOperationItem(Map<String, dynamic> operation) {
    final isExport = operation['type'] == 'export';
    final isSuccess = operation['status'] == 'success';

    return Card(
      margin: EdgeInsets.only(bottom: UIConstants.spacingSM),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(UIConstants.spacingSM),
          decoration: BoxDecoration(
            color: (isExport ? Colors.green : Colors.blue).withOpacity(0.1),
            borderRadius: BorderRadius.circular(UIConstants.radiusMD),
          ),
          child: Icon(
            isExport ? Icons.file_upload : Icons.file_download,
            color: isExport ? Colors.green : Colors.blue,
          ),
        ),
        title: Text('${isExport ? 'تصدير' : 'استيراد'} ${operation['format']}'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              DateTimeFormatter.getRelativeTime(operation['date'] as String?),
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        trailing: StatusBadge(
          status: isSuccess ? 'نجح' : 'فشل',
          showIcon: true,
        ),
      ),
    );
  }
}
