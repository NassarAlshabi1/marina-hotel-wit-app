import 'package:flutter/material.dart';

class SchemaComparisonScreen extends StatelessWidget {
  const SchemaComparisonScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('مقارنة بنية قاعدة البيانات'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showInfoDialog(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildOverviewCard(),
          const SizedBox(height: 16),
          _buildSyncFieldsComparison(),
          const SizedBox(height: 16),
          _buildNamingConventions(),
          const SizedBox(height: 16),
          _buildDataFlowDiagram(),
          const SizedBox(height: 16),
          _buildFixesSummary(),
          const SizedBox(height: 16),
          _buildRecommendations(),
        ],
      ),
    );
  }

  Widget _buildOverviewCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.compare_arrows, color: Colors.blue[700]),
                const SizedBox(width: 8),
                const Text(
                  'نظرة عامة',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildComparisonRow(
              'نوع القاعدة',
              'SQLite (Relational)',
              'NoSQL (Document)',
              Icons.storage,
            ),
            _buildComparisonRow(
              'التخزين',
              'محلي (Device)',
              'سحابي (Cloud)',
              Icons.cloud,
            ),
            _buildComparisonRow(
              'تسمية الأعمدة',
              'snake_case',
              'camelCase',
              Icons.text_fields,
            ),
            _buildComparisonRow(
              'العلاقات',
              'Foreign Keys',
              'References يدوية',
              Icons.link,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComparisonRow(
    String label,
    String localDb,
    String appwrite,
    IconData icon,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          localDb,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(Icons.arrow_forward, size: 16),
                    ),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green[50],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          appwrite,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncFieldsComparison() {
    final fields = [
      _FieldComparison('localUuid', 'TEXT UNIQUE', 'string(36)', true),
      _FieldComparison(
        'serverId',
        'INTEGER NULL',
        'integer',
        false,
        note: '⚠️ كان يحتوي UUID',
      ),
      _FieldComparison('createdAt', 'INTEGER', 'integer', true),
      _FieldComparison('updatedAt', 'INTEGER', 'integer', true),
      _FieldComparison('version', 'INTEGER', 'integer', true),
      _FieldComparison('origin', 'TEXT', 'string(20)', true),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.sync_alt, color: Colors.purple[700]),
                const SizedBox(width: 8),
                const Text(
                  'SyncFields - الحقول المشتركة',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...fields.map(_buildFieldRow),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldRow(_FieldComparison field) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: field.matches ? Colors.green[50] : Colors.orange[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: field.matches ? Colors.green[200]! : Colors.orange[200]!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                field.matches ? Icons.check_circle : Icons.warning,
                size: 16,
                color: field.matches ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 8),
              Text(
                field.name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Local: ${field.localType}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ),
              Expanded(
                child: Text(
                  'Appwrite: ${field.appwriteType}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ),
            ],
          ),
          if (field.note != null) ...[
            const SizedBox(height: 4),
            Text(
              field.note!,
              style: TextStyle(
                fontSize: 11,
                color: Colors.orange[900],
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNamingConventions() {
    final examples = [
      _NamingExample('server_id', 'serverId', '⚠️ سبب الخطأ الرئيسي'),
      _NamingExample('local_uuid', 'localUuid', '✅ مفتاح رئيسي'),
      _NamingExample('room_number', 'roomNumber', '✅ يعمل'),
      _NamingExample('booking_local_id', 'bookingLocalId', '✅ يعمل'),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.code, color: Colors.indigo[700]),
                const SizedBox(width: 8),
                const Text(
                  'اتفاقيات التسمية',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...examples.map(_buildNamingRow),
          ],
        ),
      ),
    );
  }

  Widget _buildNamingRow(_NamingExample example) {
    final isWarning = example.note.contains('⚠️');

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isWarning ? Colors.orange[50] : Colors.green[50],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              example.sqlName,
              style: const TextStyle(
                fontSize: 13,
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Icon(Icons.arrow_forward, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              example.dartName,
              style: const TextStyle(
                fontSize: 13,
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            example.note,
            style: TextStyle(
              fontSize: 11,
              color: isWarning ? Colors.orange[900] : Colors.green[900],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataFlowDiagram() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.timeline, color: Colors.teal[700]),
                const SizedBox(width: 8),
                const Text(
                  'تدفق البيانات',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildFlowStep(
              '1',
              'Local DB (SQLite)',
              'server_id, room_number',
              Colors.blue,
            ),
            _buildFlowArrow(),
            _buildFlowStep(
              '2',
              'Adapter.toJson()',
              'تحويل snake_case → camelCase',
              Colors.purple,
            ),
            _buildFlowArrow(),
            _buildFlowStep(
              '3',
              'UUID Detection ⭐',
              'تجاهل UUID في حقول integer',
              Colors.orange,
            ),
            _buildFlowArrow(),
            _buildFlowStep(
              '4',
              'Appwrite Cloud',
              'serverId, roomNumber',
              Colors.green,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFlowStep(String num, String title, String detail, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: color,
            child: Text(
              num,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlowArrow() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 4, horizontal: 24),
      child: Icon(Icons.arrow_downward, size: 20, color: Colors.grey),
    );
  }

  Widget _buildFixesSummary() {
    final fixes = [
      _FixSummary(
        'FormatException في Dashboard',
        'Error handling في Repositories',
        2,
        Icons.dashboard,
        Colors.red,
      ),
      _FixSummary(
        'FOREIGN KEY orphan data',
        'DatabaseFixer service',
        2,
        Icons.broken_image,
        Colors.orange,
      ),
      _FixSummary(
        'SQL column names mismatch',
        'استخدام server_id بدلاً من serverId',
        1,
        Icons.text_fields,
        Colors.blue,
      ),
      _FixSummary(
        'UUID conversion في Backup',
        'UUID detection في 11 Adapter',
        11,
        Icons.backup,
        Colors.green,
      ),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.build_circle, color: Colors.green[700]),
                const SizedBox(width: 8),
                const Text(
                  'الإصلاحات المنفذة اليوم',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...fixes.map(_buildFixRow),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'الإجمالي:',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  '18 ملف معدل',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.green[700],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFixRow(_FixSummary fix) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: fix.color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(fix.icon, color: fix.color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fix.problem,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: fix.color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  fix.solution,
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ],
            ),
          ),
          CircleAvatar(
            radius: 14,
            backgroundColor: fix.color,
            child: Text(
              '${fix.filesModified}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendations() {
    return Card(
      color: Colors.blue[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lightbulb, color: Colors.blue[700]),
                const SizedBox(width: 8),
                const Text(
                  'التوصيات',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildRecommendation(
              '1',
              'شغّل أداة إصلاح قاعدة البيانات',
              'إعدادات → إصلاح قاعدة البيانات',
            ),
            _buildRecommendation(
              '2',
              'اعمل نسخة احتياطية بعد الإصلاح',
              'للحفاظ على البيانات النظيفة',
            ),
            _buildRecommendation(
              '3',
              'راقب سجلات المزامنة',
              'للتأكد من عدم تكرار الأخطاء',
            ),
            _buildRecommendation(
              '4',
              'تحقق من Appwrite Schema',
              'تأكد من وجود جميع الـ 12 Collection',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecommendation(String num, String title, String detail) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: Colors.blue[700],
            child: Text(
              num,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  detail,
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('معلومات المقارنة'),
        content: const SingleChildScrollView(
          child: Text(
            'هذه الشاشة توضح المقارنة بين:\n\n'
            '• Local DB (SQLite) - قاعدة البيانات المحلية\n'
            '• Appwrite Cloud - السحابة\n\n'
            'الاختلافات الرئيسية:\n'
            '- تسمية الأعمدة (snake_case vs camelCase)\n'
            '- طبيعة القاعدة (SQL vs NoSQL)\n'
            '- معالجة البيانات (Adapters)\n\n'
            'تم إصلاح جميع الأخطاء المتعلقة بـ:\n'
            '✓ تحويل UUID إلى integer\n'
            '✓ orphan data\n'
            '✓ SQL column names\n'
            '✓ Error handling',
            style: TextStyle(fontSize: 14),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('حسناً'),
          ),
        ],
      ),
    );
  }
}

class _FieldComparison {

  _FieldComparison(
    this.name,
    this.localType,
    this.appwriteType,
    this.matches, {
    this.note,
  });
  final String name;
  final String localType;
  final String appwriteType;
  final bool matches;
  final String? note;
}

class _NamingExample {

  _NamingExample(this.sqlName, this.dartName, this.note);
  final String sqlName;
  final String dartName;
  final String note;
}

class _FixSummary {

  _FixSummary(
    this.problem,
    this.solution,
    this.filesModified,
    this.icon,
    this.color,
  );
  final String problem;
  final String solution;
  final int filesModified;
  final IconData icon;
  final Color color;
}
