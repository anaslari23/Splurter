import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:continuity_core/continuity_core.dart';

import 'package:continuity_ui/continuity_ui.dart';
import 'package:continuity_state/continuity_state.dart';
import 'package:platform_bindings/platform_bindings.dart';
import 'package:shared_types/shared_types.dart';
import 'firebase_options.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // Disable persistence on macOS to prevent LevelDB file lock conflicts
  FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: false);

  runApp(
    ProviderScope(
      overrides: [
        deviceIdProvider.overrideWithValue('mac-device-id'),
        deviceInfoProvider.overrideWithValue(buildDeviceInfo('mac-device-id', kDefaultPort)),
      ],
      child: const SplurterMacApp(),
    ),
  );
}


String kMacHostUid = 'mac-channel-1';

class SplurterMacApp extends ConsumerStatefulWidget {
  const SplurterMacApp({super.key});

  @override
  ConsumerState<SplurterMacApp> createState() => _SplurterMacAppState();
}

class _SplurterMacAppState extends ConsumerState<SplurterMacApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _bootRelay();
      if (mounted) setState(() {});
    });
  }


  Future<void> _bootRelay() async {
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }
    } catch (_) {}

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      kMacHostUid = user.uid;
    }

    final relay = ref.read(relayLoopProvider);
    relay.start(uid: kMacHostUid, deviceId: 'mac-device-id');
    await registerDevice(
      uid: kMacHostUid,
      deviceId: 'mac-device-id',
      platform: 'macos',
      name: 'My Mac',
    );
    relay.onClipboardReceived = (text) async {
      await writeClipboard(text);
    };
    listenClipboardChanges().listen((clip) async {
      await relay.send(
        uid: kMacHostUid,
        senderId: 'mac-device-id',
        recipientId: 'android-device-id',
        kind: RelayKind.clipboard,
        payload: {'text': clip.content},
      );
    });
  }


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
    GoRoute(path: '/transfers', builder: (context, state) => const _Home(index: 2)),
    GoRoute(path: '/settings', builder: (context, state) => const _Home(index: 3)),
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
          _DevicesView(),
          _ClipboardView(),
          _TransfersView(),
          _SettingsView(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: widget.index,
        onDestinationSelected: (i) => _go(i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.devices), label: 'Devices'),
          NavigationDestination(icon: Icon(Icons.content_paste), label: 'Clipboard'),
          NavigationDestination(icon: Icon(Icons.swap_horiz), label: 'Transfers'),
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
        context.go('/transfers');
        break;
      case 3:
        context.go('/settings');
        break;
    }
  }
}


class _DevicesView extends ConsumerWidget {
  const _DevicesView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pairingState = ref.watch(pairingStateProvider);
    final Device? pairedDevice = pairingState is PairingConnected ? pairingState.device : null;

    final invitationCode = PairingInvitation(
      version: RelayEnvelope.currentVersion,
      hostUid: kMacHostUid,
      pairId: 'pair-mac-1',
      device: PairedDevice(
        id: 'mac-device-id',
        name: 'My Mac',
        platform: 'macos',
        publicKey: 'pubkey-mac-1',
        capabilities: {Capability.clipboard, Capability.fileTransfer, Capability.notifications},
        pairedAt: DateTime.now(),
      ),
      expiresAt: DateTime.now().add(const Duration(days: 365)),
    ).toCode();

    // Listen to real-time device registration stream from Firestore under kMacHostUid
    final remoteDevicesAsync = ref.watch(remoteDevicesStreamProvider(kMacHostUid));

    final remoteDevices = remoteDevicesAsync.asData?.value ?? [];

    final secondaryDevice = remoteDevices.firstWhere(
      (d) => d.id != 'mac-device-id',
      orElse: () => const Device(
        id: '',
        name: '',
        platform: '',
        address: '',
        port: 0,
        version: '',
        capabilities: [],
        isPaired: false,
      ),
    );

    final hasRemoteDevice = secondaryDevice.id.isNotEmpty;

    // Automatically complete pairing if secondary device is detected in Firestore
    if (hasRemoteDevice && pairedDevice == null) {
      Future.microtask(() {
        ref.read(pairingStateProvider.notifier).complete(secondaryDevice);
      });
    }

    final activeDevice = pairedDevice ?? (hasRemoteDevice ? secondaryDevice : null);


    return Scaffold(
      appBar: AppBar(
        title: const Text('Devices'),
        actions: [
          if (activeDevice != null)
            IconButton(
              icon: const Icon(Icons.link_off),
              tooltip: 'Unpair',
              onPressed: () async {
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(kMacHostUid)
                    .collection('devices')
                    .doc(activeDevice.id)
                    .delete();
                await ref.read(pairingStateProvider.notifier).unpair();
              },

            ),

        ],
      ),
      body: activeDevice != null
          ? ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
                  ),

                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Connected to ${activeDevice.name}',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green.shade300,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Always-On Native Continuity • Direct Wi-Fi & Cloud Relay',
                              style: TextStyle(fontSize: 12, color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                DeviceCard(device: activeDevice),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: () async {
                    await FirebaseFirestore.instance
                        .collection('users')
                        .doc(kMacHostUid)
                        .collection('devices')
                        .doc(activeDevice.id)
                        .delete();
                    await ref.read(pairingStateProvider.notifier).unpair();
                  },

                  icon: const Icon(Icons.link_off),
                  label: const Text('Unpair Device'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                  ),
                ),

              ],
            )
          : remoteDevicesAsync.isLoading
              ? const Center(

                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Connecting to paired Android device...'),
                    ],
                  ),
                )
              : PairingScreen(pairingCode: invitationCode),
    );
  }
}




class _ClipboardView extends ConsumerWidget {
  const _ClipboardView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(clipHistoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Clipboard'),
        actions: [
          if (history.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => ref.read(clipHistoryProvider.notifier).clear(),
            ),
        ],
      ),
      body: ClipboardHistoryScreen(
        clipItems: history,
        onItemDelete: (item) => ref.read(clipHistoryProvider.notifier).remove(item.id),
      ),
    );
  }
}

class _TransfersView extends ConsumerWidget {
  const _TransfersView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transfers = ref.watch(transfersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Transfers')),
      body: TransferScreen(
        transfers: transfers,
        onOpenFile: (id) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Opening file $id...')),
          );
        },
        onCancel: (id) {
          ref.read(transfersProvider.notifier).cancel(id);
        },
      ),
    );
  }
}

class _SettingsView extends ConsumerWidget {
  const _SettingsView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clipSync = ref.watch(clipboardSyncEnabledProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Clipboard Sync'),
            subtitle: const Text('Automatically share NSPasteboard with paired device'),
            value: clipSync,
            onChanged: (val) {
              ref.read(clipboardSyncEnabledProvider.notifier).state = val;
            },
          ),
        ],
      ),
    );
  }
}


