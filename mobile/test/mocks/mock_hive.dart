// test/mocks/mock_hive.dart
// Mock لـ Hive للاختبارات

import 'dart:async';
import 'dart:typed_data';

/// Mock لـ Hive Box
class MockHiveBox<T> {
  final Map<String, T> _data = {};
  final String name;
  final StreamController<String> _changeController =
      StreamController<String>.broadcast();

  MockHiveBox(this.name);

  T? get(String key) => _data[key];

  Future<void> put(String key, T value) async {
    _data[key] = value;
    _changeController.add(key);
  }

  Future<void> putAll(Map<String, T> entries) async {
    _data.addAll(entries);
    for (final key in entries.keys) {
      _changeController.add(key);
    }
  }

  Future<void> delete(String key) async {
    _data.remove(key);
    _changeController.add(key);
  }

  Future<void> deleteAll(Iterable<String> keys) async {
    for (final key in keys) {
      _data.remove(key);
    }
    _changeController.add('batch_delete');
  }

  Future<void> clear() async {
    _data.clear();
    _changeController.add('clear');
  }

  bool containsKey(String key) => _data.containsKey(key);

  List<String> get keys => _data.keys.toList();

  List<T> get values => _data.values.toList();

  int get length => _data.length;

  bool get isEmpty => _data.isEmpty;

  bool get isNotEmpty => _data.isNotEmpty;

  Stream<String> watch() => _changeController.stream;

  Future<void> close() async {
    await _changeController.close();
  }

  // للاختبار
  void reset() => _data.clear();
}

/// Mock لـ Hive Lazy Box
class MockHiveLazyBox<T> extends MockHiveBox<T> {
  MockHiveLazyBox(super.name);

  Future<T?> getAsync(String key) async => get(key);

  Future<Map<String, T>> toMap() async => Map.fromEntries(
        keys.map((k) => MapEntry(k, get(k)!)),
      );
}

/// Mock لـ Hive
class MockHive {
  static final MockHive _instance = MockHive._internal();
  factory MockHive() => _instance;
  MockHive._internal();

  final Map<String, MockHiveBox<dynamic>> _boxes = {};
  final Map<String, MockHiveLazyBox<dynamic>> _lazyBoxes = {};

  Future<void> initFlutter() async {
    // لا شيء للتهيئة في الاختبار
  }

  Future<MockHiveBox<T>> openBox<T>(String name) async {
    if (!_boxes.containsKey(name)) {
      _boxes[name] = MockHiveBox<T>(name);
    }
    return _boxes[name]! as MockHiveBox<T>;
  }

  Future<MockHiveLazyBox<T>> openLazyBox<T>(String name) async {
    if (!_lazyBoxes.containsKey(name)) {
      _lazyBoxes[name] = MockHiveLazyBox<T>(name);
    }
    return _lazyBoxes[name]! as MockHiveLazyBox<T>;
  }

  MockHiveBox<T>? box<T>(String name) => _boxes[name] as MockHiveBox<T>?;

  MockHiveLazyBox<T>? lazyBox<T>(String name) =>
      _lazyBoxes[name] as MockHiveLazyBox<T>?;

  Future<bool> boxExists(String name) async => _boxes.containsKey(name);

  Future<void> deleteBoxFromDisk(String name) async {
    _boxes.remove(name);
    _lazyBoxes.remove(name);
  }

  void reset() {
    for (final box in _boxes.values) {
      box.close();
    }
    for (final box in _lazyBoxes.values) {
      box.close();
    }
    _boxes.clear();
    _lazyBoxes.clear();
  }
}

/// Mock للـ Hive Cipher (للتشفير)
class MockHiveCipher {
  Uint8List encrypt(Uint8List data) => data;
  Uint8List decrypt(Uint8List data) => data;
}

/// Mock للـ Hive AES Cipher
class MockHiveAesCipher implements MockHiveCipher {
  final List<int> key;

  MockHiveAesCipher(this.key);

  @override
  Uint8List encrypt(Uint8List data) {
    // Mock بسيط - في الواقع يستخدم AES
    return data;
  }

  @override
  Uint8List decrypt(Uint8List data) {
    // Mock بسيط - في الواقع يستخدم AES
    return data;
  }
}

/// Mock للـ Hive Reader
class MockHiveReader {
  final Map<String, dynamic> _data;

  MockHiveReader(this._data);

  dynamic read() => _data;
}

/// Mock للـ Hive Writer
class MockHiveWriter {
  final Map<String, dynamic> _data = {};

  void write(dynamic value) {
    if (value is Map) {
      _data.addAll(value.map((k, v) => MapEntry(k.toString(), v)));
    }
  }

  Map<String, dynamic> get data => _data;
}

/// Mock للـ Hive TypeAdapter
abstract class MockHiveTypeAdapter<T> {
  int get typeId;

  T read(MockHiveReader reader);
  void write(MockHiveWriter writer, T obj);
}

/// Helper للاختبارات
class HiveTestHelper {
  /// إنشاء Mock Box جاهز للاختبار
  static MockHiveBox<T> createMockBox<T>(
    String name, {
    Map<String, T>? initialData,
  }) {
    final box = MockHiveBox<T>(name);
    if (initialData != null) {
      initialData.forEach((key, value) {
        box._data[key] = value;
      });
    }
    return box;
  }

  /// إنشاء Mock Lazy Box جاهز للاختبار
  static MockHiveLazyBox<T> createMockLazyBox<T>(
    String name, {
    Map<String, T>? initialData,
  }) {
    final box = MockHiveLazyBox<T>(name);
    if (initialData != null) {
      initialData.forEach((key, value) {
        box._data[key] = value;
      });
    }
    return box;
  }

  /// مسح جميع الـ Mock Boxes
  static void resetAll() {
    MockHive().reset();
  }
}

/// Extension للـ MockHiveBox للوصول إلى _data للاختبار
extension MockHiveBoxTestExtension<T> on MockHiveBox<T> {
  Map<String, T> get testData => _data;
}
