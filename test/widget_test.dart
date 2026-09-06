import 'package:flutter_test/flutter_test.dart';

import 'package:cystem/app.dart';

void main() {
  testWidgets('Cystem app builds', (tester) async {
    await tester.pumpWidget(const CystemApp());
    expect(find.text('CYSTEM'), findsOneWidget);
  });
}
