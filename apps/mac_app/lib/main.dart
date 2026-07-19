import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:continuity_ui/continuity_ui.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: SplurterMacApp()));
}

class SplurterMacApp extends StatelessWidget {
  const SplurterMacApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Splurter',
      debugShowCheckedModeBanner: false,
      theme: SplurterTheme.light,
      darkTheme: SplurterTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: _router,
    );
  }
}

final _router = GoRouter(
  initialLocation: '/devices',
  routes: [
    GoRoute(path: '/devices', builder: (context, state) => const _Home(index: 0)),
    GoRoute(path: '/clipboard', builder: (context, state) => const _Home(index: 1)),
    GoRoute(path: '/settings', builder: (context, state) => const _Home(index: 2)),
  ],
);

class _Home extends StatefulWidget {
  const _Home({required this.index});

  final int index;

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: widget.index,
        children: const [
          _DevicesPlaceholder(),
          _ClipboardPlaceholder(),
          _SettingsPlaceholder(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: widget.index,
        onDestinationSelected: (i) => _go(i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.devices), label: 'Devices'),
          NavigationDestination(icon: Icon(Icons.content_paste), label: 'Clipboard'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }

  void _go(int i) {
    switch (i) {
      case 0:
        context.go('/devices');
        break;
      case 1:
        context.go('/clipboard');
        break;
      case 2:
        context.go('/settings');
        break;
    }
  }
}

class _DevicesPlaceholder extends StatelessWidget {
  const _DevicesPlaceholder();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Devices')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.devices,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No devices found',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Waiting for Mac discovery to be wired up.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ClipboardPlaceholder extends StatelessWidget {
  const _ClipboardPlaceholder();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Clipboard')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.content_paste_off,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'Clipboard sync coming soon',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsPlaceholder extends StatelessWidget {
  const _SettingsPlaceholder();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.settings,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'Settings coming soon',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
