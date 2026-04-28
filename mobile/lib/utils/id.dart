import 'package:uuid/uuid.dart';

class IdGen {
  static final _uuid = const Uuid();
  static String uuid() => _uuid.v4();
}
