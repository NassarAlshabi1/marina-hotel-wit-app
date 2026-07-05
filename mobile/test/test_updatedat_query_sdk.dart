import 'dart:io';
import 'package:appwrite/appwrite.dart';

void main() async {
  // تجاوز التحقق من الشهادة إن لزم
  HttpOverrides.global = _MyHttpOverrides();

  final client = Client()
    ..setEndpoint('https://fra.cloud.appwrite.io/v1')
    ..setProject('6a2b01d0000752ce97e7')
    ..addHeader('X-Appwrite-Key',
        'standard_721adc4e95401dab9274bc2a7596ce0a61bfcdf7bbe37e7c64d52fb2113414e27c8d3e8f1977ebaafcf8ae63e7f3c873aad38c2a07e3ab93229cd7cd745a3ad2f6b9ec3fc407e8abfae2be3e5be00315f4d4a74cc07bc5ba5b0eda13e4569c8ee8ce2532a7bd43d827c7b83a84495974b9995d12f031e2bead685cebbe31aa3d');

  final databases = Databases(client);

  try {
    print('=== Test 1: greaterThan on \$updatedAt ===');
    final result = await databases.listDocuments(
      databaseId: '6a2b030d000445596163',
      collectionId: 'payments',
      queries: [
        Query.greaterThan('\$updatedAt', '2026-07-04T00:00:00.000Z'),
        Query.limit(3),
      ],
    );
    print('SUCCESS: count = \${result.documents.length}');
    for (final doc in result.documents) {
      print('  id=\${doc.\$id} updatedAt=\${doc.\$updatedAt}');
    }

    print('');
    print('=== Test 2: orderDesc on \$updatedAt ===');
    final result2 = await databases.listDocuments(
      databaseId: '6a2b030d000445596163',
      collectionId: 'payments',
      queries: [
        Query.orderDesc('\$updatedAt'),
        Query.limit(3),
      ],
    );
    print('SUCCESS: count = \${result2.documents.length}');
    for (final doc in result2.documents) {
      print('  id=\${doc.\$id} updatedAt=\${doc.\$updatedAt}');
    }

    print('');
    print('=== Test 3: greaterThan future (should be 0) ===');
    final result3 = await databases.listDocuments(
      databaseId: '6a2b030d000445596163',
      collectionId: 'payments',
      queries: [
        Query.greaterThan('\$updatedAt', '2026-12-31T00:00:00.000Z'),
        Query.limit(3),
      ],
    );
    print('SUCCESS: count = \${result3.documents.length} (should be 0)');

    print('');
    print('=== ALL TESTS PASSED: \$updatedAt is queryable ===');
    exit(0);
  } catch (e) {
    print('FAILED: \$e');
    exit(1);
  }
}

class _MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (cert, host, port) => true;
  }
}
