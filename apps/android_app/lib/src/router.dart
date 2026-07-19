import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';

import './devices/devices_screen.dart';
import './clipboard/clipboard_screen.dart';
import './settings/settings_screen.dart';

const _destinations = [
  NavigationDestination(icon: Icon(Icons.devices), label: 'Devices'),
  NavigationDestination(icon: Icon(Icons.content_paste), label: 'Clipboard'),
  NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
];

const _routes = [
  '/devices',
  '/clipboard',
  '/settings',
];

final appRouter = GoRouter(
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
          DevicesScreen(),
          ClipboardScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: widget.index,
        onDestinationSelected: (i) => context.go(_routes[i]),
        destinations: _destinations,
      ),
    );
  }
}
