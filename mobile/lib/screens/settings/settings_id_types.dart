import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../components/app_scaffold.dart';

class SettingsIdTypesScreen extends StatefulWidget {
  const SettingsIdTypesScreen({super.key});

  @override
  State<SettingsIdTypesScreen> createState() => _SettingsIdTypesScreenState();
}

class _SettingsIdTypesScreenState extends State<SettingsIdTypesScreen> {
  List<String> _idTypes = [];
  bool _isLoading = true;
  final _typeController = TextEditingController();

  static const String _storageKey = 'custom_id_types';
  static const List<String> _defaultIdTypes = [
    'بطاقة شخصية',
    'جواز سفر',
    'رخصة قيادة',
    'بطاقة عسكرية',
    'استبيان',
    'شهادة ميلاد',
  ];

  @override
  void initState() {
    super.initState();
    _loadIdTypes();
  }

  Future<void> _loadIdTypes() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTypes = prefs.getStringList(_storageKey);
    setState(() {
      _idTypes = savedTypes ?? List.from(_defaultIdTypes);
      _isLoading = false;
    });
  }

  Future<void> _saveIdTypes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_storageKey, _idTypes);
  }

  void _addIdType() {
    final newType = _typeController.text.trim();
    if (newType.isNotEmpty && !_idTypes.contains(newType)) {
      setState(() {
        _idTypes.add(newType);
        _typeController.clear();
      });
      _saveIdTypes();
    }
  }

  void _removeIdType(int index) {
    setState(() {
      _idTypes.removeAt(index);
    });
    _saveIdTypes();
  }

  void _editIdType(int index) {
    _typeController.text = _idTypes[index];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تعديل نوع الهوية'),
        content: TextField(
          controller: _typeController,
          decoration: const InputDecoration(hintText: 'أدخل النوع الجديد'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              final updatedType = _typeController.text.trim();
              if (updatedType.isNotEmpty) {
                setState(() {
                  _idTypes[index] = updatedType;
                  _typeController.clear();
                });
                _saveIdTypes();
                Navigator.pop(context);
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'إعدادات أنواع الهوية',
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _typeController,
                          decoration: const InputDecoration(
                            labelText: 'إضافة نوع هوية جديد',
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _addIdType(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: _addIdType,
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Expanded(
                  child: _idTypes.isEmpty
                      ? const Center(child: Text('لا توجد أنواع هوية مضافة'))
                      : ListView.builder(
                          itemCount: _idTypes.length,
                          itemBuilder: (context, index) {
                            return ListTile(
                              leading: const Icon(Icons.badge_outlined),
                              title: Text(_idTypes[index]),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit,
                                        color: Colors.blue),
                                    onPressed: () => _editIdType(index),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete,
                                        color: Colors.red),
                                    onPressed: () => _removeIdType(index),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    'هذه القائمة ستظهر في شاشة إضافة حجز جديد عند اختيار نوع الهوية.',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
    );
  }
}
