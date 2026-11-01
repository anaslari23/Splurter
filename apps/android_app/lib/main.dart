import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:continuity_core/continuity_core.dart';
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
  Timer? _aestheticsTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootRelay();
    });
  }

  @override
  void dispose() {
    _aestheticsTimer?.cancel();
    super.dispose();
  }

  Future<void> _syncAesthetics(String hostUid, String? localIp) async {
    final targetUids = {hostUid};
    for (final uid in targetUids) {
      try {
        final status = await const MethodChannel('splurter/permissions').invokeMapMethod<String, dynamic>('getDeviceAesthetics');
        final deviceName = status?['deviceName'] as String? ?? 'Android Phone';
        await registerDevice(
          uid: uid,
          deviceId: kAndroidDeviceId,
          platform: 'android',
          name: deviceName,
          ipAddress: localIp,
          batteryLevel: status?['batteryLevel'] as int? ?? 88,
          isCharging: status?['isCharging'] as bool? ?? false,
          carrier: status?['carrier'] as String? ?? '5G',
          wallpaperTheme: status?['wallpaperTheme'] as String? ?? 'aurora',
        );
      } catch (_) {
        await registerDevice(
          uid: uid,
          deviceId: kAndroidDeviceId,
          platform: 'android',
          name: 'Android Phone',
          ipAddress: localIp,
        );
      }
    }
  }

  Future<void> _bootRelay() async {
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }
    } catch (_) {}

    final pairingState = ref.read(pairingStateProvider);
    final pairedDevice = pairingState is PairingConnected ? pairingState.device : null;

    final relay = ref.read(relayLoopProvider);
    relay.onClipboardReceived = (text) async {
      await writeClipboard(text);
    };

    final localIp = await getLocalIpAddress();
    final savedHostUid = await getHostUid();
    final hostUid = savedHostUid ?? (pairedDevice != null && pairedDevice.address.isNotEmpty ? pairedDevice.address : null) ?? FirebaseAuth.instance.currentUser?.uid ?? 'mac-channel-1';
    await setHostUid(hostUid);
    relay.start(uid: hostUid, deviceId: kAndroidDeviceId);
    if (pairedDevice != null) {
      await _syncAesthetics(hostUid, localIp);
      _aestheticsTimer?.cancel();
      _aestheticsTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        _syncAesthetics(hostUid, localIp);
      });
    }

    const MethodChannel('splurter/notifications').setMethodCallHandler((call) async {
      if (call.method == 'onNotificationPosted' || call.method == 'onNotificationRemoved') {
        final payload = Map<String, dynamic>.from(call.arguments as Map? ?? {});
        payload['action'] = call.method == 'onNotificationRemoved' ? 'remove' : 'post';
        final relay = ref.read(relayLoopProvider);
        if (relay.isConnected && relay.currentUid != null && relay.currentUid!.isNotEmpty) {
          final snap = await FirebaseFirestore.instance
              .collection('users')
              .doc(relay.currentUid!)
              .collection('devices')
              .get();
          for (final doc in snap.docs) {
            if (doc.id != kAndroidDeviceId) {
              await relay.send(
                uid: relay.currentUid!,
                senderId: kAndroidDeviceId,
                recipientId: doc.id,
                kind: RelayKind.notification,
                payload: payload,
              );
            }
          }
        }
      }
    });

    startForegroundService();
    const MethodChannel('splurter/notifications').invokeMethod('syncActiveNotifications').ignore();

    listenCallEvents().listen((callEvent) async {
      final relay = ref.read(relayLoopProvider);
      if (relay.isConnected && relay.currentUid != null && relay.currentUid!.isNotEmpty) {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(relay.currentUid!)
            .collection('devices')
            .get();
        for (final doc in snap.docs) {
          if (doc.id != kAndroidDeviceId) {
            await relay.send(
              uid: relay.currentUid!,
              senderId: kAndroidDeviceId,
              recipientId: doc.id,
              kind: RelayKind.call,
              payload: callEvent.toJson(),
            );
          }
        }
      }
    });


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
    final hostUid = (pairedDevice != null && pairedDevice.address.isNotEmpty ? pairedDevice.address : user?.uid);

    if (hostUid != null) {
      final remoteDevicesAsync = ref.watch(remoteDevicesStreamProvider(hostUid));
      if (remoteDevicesAsync.hasValue) {
        final remoteDevices = remoteDevicesAsync.asData?.value ?? [];
        final isRegisteredInCloud = remoteDevices.any((d) => d.platform != 'macos');

        if (!isRegisteredInCloud && pairedDevice != null) {
          Future.microtask(() async {
            ref.read(relayLoopProvider).stop();
            await ref.read(pairingStateProvider.notifier).unpair();
            await setHostUid(null);
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

