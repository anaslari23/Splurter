import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_types/shared_types.dart';
import 'package:continuity_ui/continuity_ui.dart';
import 'package:continuity_state/continuity_state.dart';

import 'package:platform_bindings/platform_bindings.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter/services.dart';
import 'src/router.dart';
import 'firebase_options.dart';



// WorkManager task name for keepalive
const _keepaliveTask = 'splurter.keepalive';

/// Called by WorkManager in the background to restart the foreground service
/// if the OEM killed it (Samsung, Xiaomi, etc.).
@pragma('vm:entry-point')
void _workManagerDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == _keepaliveTask) {
      try {
        await startForegroundService();
      } catch (_) {}
    }
    return true;
  });
}

String kAndroidDeviceId = 'android-device-id';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  kAndroidDeviceId = await getOrCreateDeviceId('android');

  // Register WorkManager keepalive — restarts service every 15 min if OEM killed it
  await Workmanager().initialize(_workManagerDispatcher);
  await Workmanager().registerPeriodicTask(
    _keepaliveTask,
    _keepaliveTask,
    frequency: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );

  runApp(
    ProviderScope(
      overrides: [
        deviceIdProvider.overrideWithValue(kAndroidDeviceId),
        deviceInfoProvider.overrideWithValue(buildDeviceInfo(kAndroidDeviceId, kDefaultPort)),
      ],
      child: const SplurterApp(),
    ),
  );
}

class SplurterApp extends ConsumerStatefulWidget {
  const SplurterApp({super.key});

  @override
  ConsumerState<SplurterApp> createState() => _SplurterAppState();
}

class _SplurterAppState extends ConsumerState<SplurterApp> {
  bool _batteryExemptRequested = false;
  static const _batteryChannel = MethodChannel('splurter/battery_optimization');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootRelay();
    });
  }

  Future<void> _bootRelay() async {
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }
    } catch (_) {}

    final user = FirebaseAuth.instance.currentUser;
    final pairingState = ref.read(pairingStateProvider);
    final pairedDevice = pairingState is PairingConnected ? pairingState.device : null;

    final relay = ref.read(relayLoopProvider);
    relay.onClipboardReceived = (text) async {
      await writeClipboard(text);
    };

    final localIp = await getLocalIpAddress();
    final hostUid = user?.uid ?? (pairedDevice != null && pairedDevice.address.isNotEmpty ? pairedDevice.address : null);
    if (hostUid != null) {
      relay.start(uid: hostUid, deviceId: kAndroidDeviceId);
      await registerDevice(
        uid: hostUid,
        deviceId: kAndroidDeviceId,
        platform: 'android',
        name: 'Android Device',
        ipAddress: localIp,
      );
    }

    startForegroundService();


    // Request battery exemption once — opens the direct system dialog
    if (!_batteryExemptRequested) {
      _batteryExemptRequested = true;
      _batteryChannel.invokeMethod('requestBatteryExemption').ignore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final pairingState = ref.watch(pairingStateProvider);
    final pairedDevice = pairingState is PairingConnected ? pairingState.device : null;
    final hostUid = user?.uid ?? (pairedDevice != null && pairedDevice.address.isNotEmpty ? pairedDevice.address : null);

    if (hostUid != null) {
      final remoteDevicesAsync = ref.watch(remoteDevicesStreamProvider(hostUid));
      if (remoteDevicesAsync.hasValue) {
        final remoteDevices = remoteDevicesAsync.asData?.value ?? [];
        final hasRemoteDevice = remoteDevices.any((d) => d.id != kAndroidDeviceId);
        if (!hasRemoteDevice && pairedDevice != null) {
          Future.microtask(() async {
            ref.read(relayLoopProvider).stop();
            await ref.read(pairingStateProvider.notifier).unpair();
          });
        }
      }
    }

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

