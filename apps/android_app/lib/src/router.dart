import 'package:go_router/go_router.dart';

import './devices/devices_screen.dart';
import './settings/settings_screen.dart';
import './pairing/qr_scanner_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/devices',
  routes: [
    GoRoute(path: '/devices', builder: (context, state) => const DevicesScreen()),
    GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
    GoRoute(path: '/scan', builder: (context, state) => const QrScannerScreen()),
  ],
);
