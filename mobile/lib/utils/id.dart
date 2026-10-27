import 'package:uuid/uuid.dart';

class IdGen {
  static const _uuid = Uuid();
  static String uuid() => _uuid.v4();

  /// معرّف قصير (8 أحرف) قابل للقراءة — يُستخدم في أسماء الأجهزة
  static String shortId() => _uuid.v4().substring(0, 8);
}
