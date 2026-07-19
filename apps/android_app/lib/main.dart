import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:continuity_ui/continuity_ui.dart';
import 'src/router.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: SplurterApp()));
}

class SplurterApp extends StatelessWidget {
  const SplurterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Splurter',
      debugShowCheckedModeBanner: false,
      theme: SplurterTheme.light,
      darkTheme: SplurterTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: appRouter,
    );
  }
}
