import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ffbox_edgelink/app.dart';
import 'package:ffbox_edgelink/core/config/app_config.dart';
import 'package:ffbox_edgelink/data/repositories/session_repository_impl.dart';
import 'package:ffbox_edgelink/presentation/providers/app_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final session = await SessionRepositoryImpl().load();
  runApp(
    ProviderScope(
      overrides: [
        if (session != null)
          sessionProvider.overrideWith(
            () => SessionNotifier()..update(session),
          ),
        if (session != null)
          appConfigProvider.overrideWith(
            (ref) => AppConfig(baseUrl: session.baseUrl),
          ),
      ],
      child: const FFBoxApp(),
    ),
  );
}
