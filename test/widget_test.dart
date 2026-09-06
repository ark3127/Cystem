import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cystem/core/theme/app_theme.dart';

void main() {
  testWidgets('CYSTEM theme renders', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: const Scaffold(
          body: Center(child: Text('CYSTEM')),
        ),
      ),
    );

    expect(find.text('CYSTEM'), findsOneWidget);
  });
}
