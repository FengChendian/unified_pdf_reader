import 'package:flutter_test/flutter_test.dart';

import 'package:unified_pdf_reader/main.dart';

void main() {
  testWidgets('App loads smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const PdfReaderApp());

    // Verify that the app title is displayed
    expect(find.text('Unified PDF Reader'), findsOneWidget);
  });
}
