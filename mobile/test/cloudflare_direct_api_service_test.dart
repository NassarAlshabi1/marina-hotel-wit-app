import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:marina_hotel_mobile/services/cloudflare_direct_api_service.dart';
import 'package:marina_hotel_mobile/services/cloudflare_d1_service.dart';

/// اختبارات خدمة تسجيل الارتباط المباشر مع api.cloudflare.com.
///
/// تغطي الحالات المثبتة تجريبياً (مسبارات 2026-09):
///  1. توكن حساب (بادئة cfat_) يفشل في /user/tokens/verify برمز 1000
///     رغم صحته — ثم ينجح عبر /accounts/{id}/tokens/verify.
///  2. اكتشاف معرّف الحساب تلقائياً عبر GET /accounts عند غيابه من
///     الإعدادات (مرة واحدة فقط بفضل ذاكرة النسخة).
///  3. صراحة الأخطاء: فشل نقطة الحساب يعرض أخطاء نقطة الحساب لا
///     خطأ /user المضلل (1000).
///  4. تلميح cfat_ عند تعذّر الاكتشاف.
///  5. مسار توكن المستخدم العادي عبر /user/tokens/verify حرفياً.
class _FakeCloudflareHttpClient extends http.BaseClient {
  _FakeCloudflareHttpClient(this.handler);

  final Future<http.Response> Function(Uri uri) handler;
  final List<Uri> requested = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requested.add(request.url);
    final response = await handler(request.url);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      contentLength: response.bodyBytes.length,
      headers: response.headers,
    );
  }
}

http.Response _json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

/// موجّه مسارات عام لكل الاختبارات — يستقبل خريطة استجابات بالمسار.
_FakeCloudflareHttpClient _clientFor(Map<String, Object Function()> routes) {
  return _FakeCloudflareHttpClient((uri) {
    final path = uri.path;
    for (final entry in routes.entries) {
      if (path.endsWith(entry.key) ||
          (entry.key == '/accounts' &&
              path.endsWith('/accounts') &&
              entry.key.isNotEmpty)) {
        return Future.value(_json(entry.value()));
      }
    }
    return Future.value(
      _json(<String, Object>{
        'success': false,
        'errors': <Object>[
          <String, Object>{'code': 404, 'message': 'unrouted: $path'},
        ],
      }, 404),
    );
  });
}

void main() {
  test(
    'توكن حساب cfat_ بلا معرّف محفوظ: اكتشاف تلقائي + نجاح عبر نقطة الحساب',
    () async {
      // /user يرفض التوكن رغم صحته — السلوك المؤكد تجريبياً.
      final client = _FakeCloudflareHttpClient((uri) {
        final path = uri.path;
        if (path.endsWith('/user/tokens/verify')) {
          return Future.value(
            _json(<String, Object>{
              'success': false,
              'errors': <Object>[
                <String, Object>{
                  'code': 1000,
                  'message': 'Invalid API Token',
                },
              ],
            }, 401),
          );
        }
        if (path.endsWith('/accounts') && uri.query == 'per_page=5') {
          return Future.value(
            _json(<String, Object>{
              'success': true,
              'result': <Object>[
                <String, Object>{
                  'id': 'acct123',
                  'name': 'Marina Hotel Account',
                },
              ],
            }),
          );
        }
        if (path.endsWith('/tokens/verify')) {
          return Future.value(
            _json(<String, Object>{
              'success': true,
              'result': <String, Object>{
                'id': 'tok456',
                'status': 'active',
              },
              'messages': <Object>[
                <String, Object>{
                  'code': 10000,
                  'message': 'This API Token is valid and active',
                },
              ],
            }),
          );
        }
        if (path.contains('/d1/database')) {
          return Future.value(
            _json(<String, Object>{
              'success': true,
              'result': <Object>[
                <String, Object>{
                  'uuid': 'dbuuid',
                  'name': 'marina-hotel-db',
                  'file_size': 3690496,
                },
              ],
            }),
          );
        }
        return Future.value(
          _json(<String, Object>{'success': false, 'errors': <Object>[]}, 404),
        );
      });

      final service = CloudflareDirectApiService(
        const CloudflareD1Config(
          accountId: '',
          databaseId: 'dbuuid',
          apiToken: 'cfat_testtoken',
        ),
        client: client,
      );

      final result = await service.registerConnection();

      expect(result.ok, isTrue, reason: 'المسار الكامل يجب أن ينجح');
      expect(result.verify?.endpoint, '/accounts/acct123/tokens/verify');
      expect(result.verify?.status, 'active');
      expect(result.verify?.discoveredAccountId, 'acct123');
      expect(result.account?.matchedDatabaseName, 'marina-hotel-db');
      expect(
        result.summary.any((line) => line.contains('تم اكتشاف معرّف الحساب')),
        isTrue,
        reason: 'الملخص يوضح أن المعرّف اكتُشف تلقائياً',
      );
      expect(
        result.summary.any((line) => line.contains('Marina Hotel Account')),
        isTrue,
      );

      // ذاكرة النسخة: نداء GET /accounts حصل مرة واحدة فقط رغم أن
      // verifyToken وlistAccountD1Databases كلاهما طلب المعرّف.
      final accountsCalls = client.requested
          .where((u) => u.path.endsWith('/accounts') && u.query != 'per_page=50')
          .length;
      expect(accountsCalls, 1, reason: 'اكتشاف المعرّف يُنفَّذ مرة واحدة');
    },
  );

  test(
    'فشل نقطة الحساب يعرض أخطاءها الحقيقية لا خطأ /user المضلل (1000)',
    () async {
      final client = _clientFor(<String, Object Function()>{
        '/user/tokens/verify': () => <String, Object>{
              'success': false,
              'errors': <Object>[
                <String, Object>{'code': 1000, 'message': 'Invalid API Token'},
              ],
            },
        '/accounts/acct123/tokens/verify': () => <String, Object>{
              'success': false,
              'errors': <Object>[
                <String, Object>{
                  'code': 9109,
                  'message': 'Unauthorized to use this token',
                },
              ],
            },
      });

      final service = CloudflareDirectApiService(
        const CloudflareD1Config(
          accountId: 'acct123',
          databaseId: 'dbuuid',
          apiToken: 'cfat_testtoken',
        ),
        client: client,
      );

      final verify = await service.verifyToken();

      expect(verify.ok, isFalse);
      expect(verify.endpoint, '/accounts/acct123/tokens/verify');
      expect(
        verify.errors.any((e) => e.contains('لا يملك صلاحية الوصول')),
        isTrue,
        reason: 'خطأ 9109 الحقيقي يظهر مترجماً',
      );
      expect(
        verify.errors.any((e) => e.contains('ملغى أو محذوف')),
        isFalse,
        reason: 'رسالة 1000 المضللة من /user لا تُعرض في هذا المسار',
      );
    },
  );

  test(
    'تعذّر اكتشاف المعرّف: أخطاء مدمجة صادقة + تلميح cfat_',
    () async {
      final client = _clientFor(<String, Object Function()>{
        '/user/tokens/verify': () => <String, Object>{
              'success': false,
              'errors': <Object>[
                <String, Object>{'code': 1000, 'message': 'Invalid API Token'},
              ],
            },
        '/accounts': () => <String, Object>{
              'success': false,
              'errors': <Object>[
                <String, Object>{'code': 9109, 'message': 'Unauthorized'},
              ],
            },
      });

      final service = CloudflareDirectApiService(
        const CloudflareD1Config(
          accountId: '',
          databaseId: '',
          apiToken: 'cfat_testtoken',
        ),
        client: client,
      );

      final verify = await service.verifyToken();

      expect(verify.ok, isFalse);
      expect(
        verify.errors.any((e) => e.contains('cfat_')),
        isTrue,
        reason: 'تلميح نوع التوكن يظهر عند تعذّر الاكتشاف',
      );
      expect(
        verify.errors.any((e) => e.contains('لا يملك صلاحية الوصول')),
        isTrue,
        reason: 'خطأ الاكتشاف الحقيقي يظهر',
      );
    },
  );

  test('توكن مستخدم عادي: النجاح عبر /user/tokens/verify حرفياً', () async {
    final client = _clientFor(<String, Object Function()>{
      '/user/tokens/verify': () => <String, Object>{
            'success': true,
            'result': <String, Object>{
              'id': 'tok1',
              'status': 'active',
              'expires_on': '2027-01-01T00:00:00Z',
            },
          },
      '/accounts/acctSaved/d1/database': () => <String, Object>{
            'success': true,
            'result': <Object>[
              <String, Object>{
                'uuid': 'dbSaved',
                'name': 'hotel-db',
                'file_size': 10,
              },
            ],
          },
    });

    final service = CloudflareDirectApiService(
      const CloudflareD1Config(
        accountId: 'acctSaved',
        databaseId: 'dbSaved',
        apiToken: 'usertoken',
      ),
      client: client,
    );

    final result = await service.registerConnection();

    expect(result.ok, isTrue);
    expect(result.verify?.endpoint, '/user/tokens/verify');
    expect(result.verify?.discoveredAccountId, isNull);
    expect(service.discoveredAccountId, isNull,
        reason: 'لا اكتشاف عندما يكون المعرّف محفوظاً');
    expect(result.account?.matchedDatabaseName, 'hotel-db');
    // لا نداء GET /accounts إطلاقاً في هذا المسار.
    expect(
      client.requested.where((u) => u.path.endsWith('/accounts')).isEmpty,
      isTrue,
    );
  });

  test('غياب التوكن: رسالة واضحة بلا أي نداء شبكي', () async {
    final client = _FakeCloudflareHttpClient((uri) => Future.value(_json(0)));
    final service = CloudflareDirectApiService(
      const CloudflareD1Config(accountId: '', databaseId: '', apiToken: ''),
      client: client,
    );

    final result = await service.registerConnection();

    expect(result.ok, isFalse);
    expect(result.summary.first, contains('لا يوجد توكن محفوظ'));
    expect(client.requested, isEmpty);
  });
}
