import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/utils/responsive.dart';

void main() {
  testWidgets('adaptiveColumns falls back to mobile count for invalid widths', (
    tester,
  ) async {
    int? zeroWidthColumns;
    int? infiniteWidthColumns;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(1200, 800)),
        child: Builder(
          builder: (context) {
            zeroWidthColumns = context.adaptiveColumns(
              mobile: 2,
              itemMinWidth: 0,
            );
            infiniteWidthColumns = context.adaptiveColumns(
              mobile: 2,
              itemMinWidth: double.infinity,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(zeroWidthColumns, 2);
    expect(infiniteWidthColumns, 2);
  });
}
