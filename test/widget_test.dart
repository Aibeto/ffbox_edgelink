import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ffbox_edgelink/app.dart';

void main() {
  testWidgets('app boots to login screen when no session', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: FFBoxApp()));
    expect(find.text('FFBox'), findsOneWidget);
  });
}
