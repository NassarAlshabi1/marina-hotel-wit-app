import 'package:flutter/material.dart';
import '../services/appwrite_schema_verifier.dart';

/// Script للتحقق من مطابقة Schema مع Appwrite Cloud
/// 
/// الاستخدام:
/// 1. شغل التطبيق
/// 2. اضغط على زر "التحقق من Schema" في الإعدادات
/// أو استدعي هذه الدالة من main.dart:
/// 
/// ```dart
/// await checkAppwriteSchema();
/// ```
Future<void> checkAppwriteSchema() async {
  debugPrint('🔍 جاري التحقق من Appwrite Schema...');
  
  try {
    final results = await AppwriteSchemaVerifier.verifySchema();
    
    final missingCollections = results['missing'] as List;
    final missingAttrs = results['missingAttributes'] as Map;
    
    if (missingCollections.isEmpty && missingAttrs.isEmpty) {
      debugPrint('✅ Schema مطابق تماماً - جميع الحقول موجودة');
      return;
    }
    
    if (missingCollections.isNotEmpty) {
      debugPrint('❌ Collections ناقصة:');
      for (final collection in missingCollections) {
        debugPrint('  - $collection');
      }
    }
    
    if (missingAttrs.isNotEmpty) {
      debugPrint('❌ Attributes ناقصة:');
      missingAttrs.forEach((collection, attrs) {
        debugPrint('  📂 $collection:');
        for (final attr in attrs) {
          debugPrint('    - $attr');
        }
      });
      
      // طباعة تعليمات الإضافة
      debugPrint('\n📖 لإضافة الحقول الناقصة:');
      debugPrint('1. افتح Appwrite Console');
      debugPrint('2. اذهب إلى Databases → اختر قاعدة البيانات');
      debugPrint('3. افتح Collection المطلوب');
      debugPrint('4. اضغط "Create Attribute" وأضف الحقول الناقصة');
      debugPrint('\nراجع APPWRITE_SCHEMA_UPDATE.md للتفاصيل');
    }
    
  } catch (e, stack) {
    debugPrint('❌ خطأ في التحقق من Schema: $e');
    debugPrint('Stack trace: $stack');
  }
}

/// Widget لزر التحقق (يمكن إضافته في صفحة الإعدادات)
class SchemaVerificationButton extends StatefulWidget {
  const SchemaVerificationButton({super.key});

  @override
  State<SchemaVerificationButton> createState() =>
      _SchemaVerificationButtonState();
}

class _SchemaVerificationButtonState extends State<SchemaVerificationButton> {
  bool _checking = false;
  String? _result;

  Future<void> _verify() async {
    setState(() {
      _checking = true;
      _result = null;
    });

    try {
      final results = await AppwriteSchemaVerifier.verifySchema();

      final missingCollections = results['missing'] as List;
      final missingAttrs = results['missingAttributes'] as Map;

      if (missingCollections.isEmpty && missingAttrs.isEmpty) {
        setState(() {
          _result = '✅ Schema مطابق تماماً';
        });
      } else {
        final buffer = StringBuffer();
        
        if (missingCollections.isNotEmpty) {
          buffer.writeln('❌ Collections ناقصة:');
          for (final c in missingCollections) {
            buffer.writeln('  • $c');
          }
        }
        
        if (missingAttrs.isNotEmpty) {
          buffer.writeln('❌ Attributes ناقصة:');
          missingAttrs.forEach((collection, attrs) {
            buffer.writeln('  📂 $collection:');
            for (final attr in attrs) {
              buffer.writeln('    • $attr');
            }
          });
        }
        
        setState(() {
          _result = buffer.toString();
        });
      }
    } catch (e) {
      setState(() {
        _result = '❌ خطأ: $e';
      });
    } finally {
      setState(() {
        _checking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton.icon(
          onPressed: _checking ? null : _verify,
          icon: _checking
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_circle),
          label: Text(_checking ? 'جاري التحقق...' : 'التحقق من Appwrite Schema'),
        ),
        if (_result != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _result!.contains('✅')
                  ? Colors.green.withOpacity(0.1)
                  : Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _result!.contains('✅')
                    ? Colors.green
                    : Colors.orange,
              ),
            ),
            child: Text(
              _result!,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: _result!.contains('✅') ? Colors.green : Colors.orange,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
