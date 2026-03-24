import 'package:uuid/uuid.dart';

class IdGen {
  static const _uuid = Uuid();
  static String uuid() => _uuid.v4();
}
