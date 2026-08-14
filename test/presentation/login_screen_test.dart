import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ffbox_edgelink/presentation/screens/login_screen.dart';

void main() {
  testWidgets('shows server field and login button', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: LoginScreen())),
    );
    await tester.pumpAndSettle();
    expect(find.text('SERVER'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
  });

  testWidgets('shows error when submitting empty form', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: LoginScreen())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('登录'));
    await tester.pump();
    expect(find.text('请输入服务器地址'), findsOneWidget);
  });
}
