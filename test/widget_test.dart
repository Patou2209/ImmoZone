import 'package:flutter_test/flutter_test.dart';
import 'package:immo_zone/main.dart';

void main() {
  testWidgets('ImmoZone app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ImmoZoneApp());
    expect(find.byType(SplashScreen), findsOneWidget);
  });
}
