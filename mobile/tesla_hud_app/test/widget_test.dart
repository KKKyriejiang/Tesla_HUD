import 'package:flutter_test/flutter_test.dart';
import 'package:tesla_hud_app/main.dart';

void main() {
  testWidgets('renders the Tesla HUD shell', (WidgetTester tester) async {
    await tester.pumpWidget(const TeslaHudApp());

    expect(find.text('Tesla HUD'), findsOneWidget);
    expect(find.text('Waiting for dashboard data'), findsOneWidget);
  });
}
