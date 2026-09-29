// ═══════════════════════════════════════════════════════════════
//  resilient_http_client_test.dart
//  Tests for ResilientHttpClient (DoH fallback, retry, timeout)
// ═══════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io' show GZipCodec;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marina_hotel_mobile/services/resilient_http_client.dart';

void main() {
  group('ResilientHttpClient', () {
    test('can be created with default timeout', () {
      final client = createResilientHttpClient();
      expect(client, isNotNull);
      client.close();
    });

    test('can be created with custom timeout', () {
      final client = createResilientHttpClient(
        timeout: const Duration(seconds: 60),
      );
      expect(client, isNotNull);
      client.close();
    });

    test('sends normal GET request successfully', () async {
      final mockClient = MockClient((request) async {
        return http.Response('{"status":"ok"}', 200);
      });

      final resilient = ResilientHttpClient(innerClient: mockClient);
      final response = await resilient.get(
        Uri.parse('https://example.com/api/test'),
      );

      expect(response.statusCode, equals(200));
      expect(response.body, contains('ok'));
      resilient.close();
    });

    test('sends normal POST request successfully', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, equals('POST'));
        expect(request.body, contains('test data'));
        return http.Response('{"success":true}', 201);
      });

      final resilient = ResilientHttpClient(innerClient: mockClient);
      final response = await resilient.post(
        Uri.parse('https://example.com/api/create'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'data': 'test data'}),
      );

      expect(response.statusCode, equals(201));
      expect(response.body, contains('true'));
      resilient.close();
    });

    test('returns error response from server (4xx)', () async {
      final mockClient = MockClient((request) async {
        return http.Response('{"error":"bad request"}', 400);
      });

      final resilient = ResilientHttpClient(innerClient: mockClient);
      final response = await resilient.get(
        Uri.parse('https://example.com/api/error'),
      );

      expect(response.statusCode, equals(400));
      expect(response.body, contains('bad request'));
      resilient.close();
    });

    test('returns error response from server (5xx)', () async {
      final mockClient = MockClient((request) async {
        return http.Response('{"error":"server error"}', 500);
      });

      final resilient = ResilientHttpClient(innerClient: mockClient);
      final response = await resilient.get(
        Uri.parse('https://example.com/api/crash'),
      );

      expect(response.statusCode, equals(500));
      resilient.close();
    });

    test('passes through non-HTTPS requests without interception', () async {
      final mockClient = MockClient((request) async {
        return http.Response('ok', 200);
      });

      final resilient = ResilientHttpClient(innerClient: mockClient);
      final response = await resilient.get(Uri.parse('http://example.com/api'));

      expect(response.statusCode, equals(200));
      resilient.close();
    });

    test('handles empty host gracefully', () async {
      final mockClient = MockClient((request) async {
        return http.Response('ok', 200);
      });

      final resilient = ResilientHttpClient(innerClient: mockClient);
      // This should not throw — just pass through
      expect(() async {
        await resilient.get(Uri.parse('https:///api'));
      }, returnsNormally);
      resilient.close();
    });
  });

  group('GZipCodec compression', () {
    test('compresses and decompresses JSON correctly', () {
      final original = jsonEncode({
        'operations': [
          {
            'id': '1',
            'entity': 'rooms',
            'data': {'room_number': '101'},
          },
          {
            'id': '2',
            'entity': 'rooms',
            'data': {'room_number': '102'},
          },
        ],
      });

      final codec = GZipCodec(level: 9);
      final compressed = codec.encode(utf8.encode(original));
      final decompressed = utf8.decode(codec.decode(compressed));

      expect(decompressed, equals(original));
      // Compressed should be smaller for repetitive JSON
      expect(compressed.length, lessThan(original.length));
    });

    test('compression ratio improves with larger repetitive payloads', () {
      // Small payload
      final small = jsonEncode({'a': 1});
      final smallCompressed = GZipCodec(level: 9).encode(utf8.encode(small));
      final smallRatio = smallCompressed.length / small.length;

      // Large repetitive payload
      final large = jsonEncode({
        'operations': List.generate(
          50,
          (i) => {
            'idempotencyKey': 'key-$i',
            'entity': 'rooms',
            'operation': 'create',
            'data': {
              'local_uuid': 'uuid-$i',
              'room_number': '${100 + i}',
              'type': 'standard',
              'price': 15000,
              'status': 'available',
              'created_at': 1785549900,
              'updated_at': 1785549900,
              'last_modified': 1785549900,
              'version': 1,
              'vector_clock': '{}',
              'origin': 'cloud',
              'device_id': 'test',
            },
          },
        ),
      });
      final largeCompressed = GZipCodec(level: 9).encode(utf8.encode(large));
      final largeRatio = largeCompressed.length / large.length;

      // Large payload should compress better (lower ratio)
      expect(largeRatio, lessThan(smallRatio));
      expect(largeRatio, lessThan(0.5)); // Should be <50% of original
    });
  });

  group('HTTP headers', () {
    test('sends custom headers correctly', () async {
      final mockClient = MockClient((request) async {
        expect(request.headers['Authorization'], equals('Bearer test-token'));
        expect(request.headers['Content-Type'], equals('application/json'));
        return http.Response('{"ok":true}', 200);
      });

      final resilient = ResilientHttpClient(innerClient: mockClient);
      await resilient.post(
        Uri.parse('https://example.com/api'),
        headers: {
          'Authorization': 'Bearer test-token',
          'Content-Type': 'application/json',
        },
        body: '{"test":true}',
      );
      resilient.close();
    });

    test('sends gzip Content-Encoding header', () async {
      final mockClient = MockClient((request) async {
        expect(request.headers['Content-Encoding'], equals('gzip'));
        return http.Response('{"ok":true}', 200);
      });

      final resilient = ResilientHttpClient(innerClient: mockClient);
      final compressed = GZipCodec(
        level: 9,
      ).encode(utf8.encode('{"test":true}'));
      await resilient.post(
        Uri.parse('https://example.com/api'),
        headers: {
          'Content-Type': 'application/json',
          'Content-Encoding': 'gzip',
        },
        body: compressed,
      );
      resilient.close();
    });
  });

  group('DoH provider roster', () {
    test('includes the account Zero Trust Gateway resolver as 7th writer', () {
      final roster = ResilientHttpClient.describeDohEndpointsForTests();

      // سبعة كتّاب بعد دمج بوابة الحساب (2026-09-28)
      expect(roster.length, equals(7));

      final gateway = roster
          .where(
            (e) => (e['hostname']! as String).endsWith(
              '.cloudflare-gateway.com',
            ),
          )
          .toList();
      expect(gateway.length, equals(1));
      expect(gateway.first['hostname'], equals('nassaralshabi.cloudflare-gateway.com'));
      expect(gateway.first['path'], equals('/dns-query'));
      expect(
        gateway.first['ips'],
        containsAll(<String>['162.159.36.20', '162.159.36.5']),
      );
    });

    test('every provider is fully specified (hardcoded IPs, JSON API path)', () {
      for (final e in ResilientHttpClient.describeDohEndpointsForTests()) {
        expect((e['hostname']! as String).isNotEmpty, isTrue);
        expect(
          e['path']! as String,
          anyOf(equals('/dns-query'), equals('/resolve')),
          reason: '${e['hostname']} path غير متوقع',
        );
        expect(
          (e['ips']! as List<String>).where((ip) => ip.isNotEmpty),
          isNotEmpty,
          reason: '${e['hostname']} بلا عناوين مثبتة',
        );
      }
    });

    test('google resolver keeps its dedicated /resolve JSON path', () {
      final roster = ResilientHttpClient.describeDohEndpointsForTests();
      final google = roster.firstWhere(
        (e) => e['hostname'] == 'dns.google',
      );
      expect(google['path'], equals('/resolve'));
    });
  });
}
