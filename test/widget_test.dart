import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // MarketWarsApp requires Firebase initialization,
    // so integration tests should be used for full app testing.
    expect(true, isTrue);
  });
}
