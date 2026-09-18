// Performance utility: offload heavy JSON parsing to Isolates.
//
// On weak devices (1-2 GB RAM, low CPU), parsing large JSON payloads on
// the main thread causes visible jank and ANR (Application Not Responding).
// This utility wraps jsonDecode/jsonEncode in Isolate.run() for payloads
// above a size threshold, keeping the main thread free for UI rendering.
//
// Usage:
//   final data = await JsonIsolate.decode(rawJsonString);
//   final json = await JsonIsolate.encode(myMap);
//
// Threshold: payloads > 4KB are offloaded to an isolate.
// Smaller payloads run on the main thread (isolate spawn overhead > gain).

import 'dart:convert';
import 'dart:isolate';

class JsonIsolate {
  JsonIsolate._();

  /// Minimum payload size (in bytes) to justify isolate offloading.
  /// Below this, the isolate spawn overhead exceeds the parsing time.
  static const int _isolateThreshold = 4096;

  /// Decodes a JSON string. Offloads to isolate if payload > 4KB.
  static Future<dynamic> decode(String jsonString) async {
    if (jsonString.length < _isolateThreshold) {
      return jsonDecode(jsonString);
    }
    return Isolate.run(() => jsonDecode(jsonString));
  }

  /// Encodes an object to JSON string. Offloads to isolate if result > 4KB.
  static Future<String> encode(Object? value) async {
    // For encoding, we can't know the size beforehand, so we check the
    // input complexity: if it's a Map/List with > 50 entries, use isolate.
    if (_estimateSize(value) < _isolateThreshold) {
      return jsonEncode(value);
    }
    return Isolate.run(() => jsonEncode(value));
  }

  /// Decodes a JSON string as Map<String, dynamic>.
  static Future<Map<String, dynamic>> decodeAsMap(String jsonString) async {
    final result = await decode(jsonString);
    return Map<String, dynamic>.from(result as Map);
  }

  /// Decodes a JSON string as List<dynamic>.
  static Future<List<dynamic>> decodeAsList(String jsonString) async {
    final result = await decode(jsonString);
    return List<dynamic>.from(result as List);
  }

  /// Rough size estimate without full encoding.
  static int _estimateSize(Object? value) {
    if (value == null) return 4;
    if (value is String) return value.length + 2;
    if (value is num || value is bool) return 8;
    if (value is Map) {
      int size = 2;
      for (final entry in value.entries) {
        size += _estimateSize(entry.key) + _estimateSize(entry.value) + 3;
      }
      return size;
    }
    if (value is List) {
      int size = 2;
      for (final item in value) {
        size += _estimateSize(item) + 1;
      }
      return size;
    }
    return 32;
  }

  /// Batch decode: decodes multiple JSON strings in a single isolate call.
  /// Useful for sync operations that process many outbox entries.
  static Future<List<dynamic>> decodeBatch(List<String> jsonStrings) async {
    if (jsonStrings.isEmpty) return [];
    // If total size is small, decode on main thread
    final totalSize = jsonStrings.fold<int>(0, (sum, s) => sum + s.length);
    if (totalSize < _isolateThreshold) {
      return jsonStrings.map(jsonDecode).toList();
    }
    return Isolate.run(() => jsonStrings.map(jsonDecode).toList());
  }
}
