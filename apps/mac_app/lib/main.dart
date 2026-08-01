import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:continuity_core/continuity_core.dart';

import 'package:continuity_ui/continuity_ui.dart';
import 'package:continuity_state/continuity_state.dart';
import 'package:platform_bindings/platform_bindings.dart';
import 'package:shared_types/shared_types.dart';
import 'firebase_options.dart';

String kMacHostUid = 'mac-channel-1';
String kMacDeviceId = 'mac-device-id';

final isCompactModeProvider = StateProvider<bool>((ref) => false);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // Disable persistence on macOS to prevent LevelDB file lock conflicts
  FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: false);
  kMacDeviceId = await getOrCreateDeviceId('mac');

  runApp(
    ProviderScope(
      overrides: [
        deviceIdProvider.overrideWithValue(kMacDeviceId),
        deviceInfoProvider.overrideWithValue(buildDeviceInfo(kMacDeviceId, kDefaultPort)),
      ],
      child: const SplurterMacApp(),
    ),
  );
}

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

    final localIp = await getLocalIpAddress();
    final relay = ref.read(relayLoopProvider);
    relay.start(uid: kMacHostUid, deviceId: kMacDeviceId);
    await registerDevice(
      uid: kMacHostUid,
      deviceId: kMacDeviceId,
      platform: 'macos',
      name: 'My Mac',
      ipAddress: localIp,
    );
    relay.onClipboardReceived = (text) async {
      await writeClipboard(text);
    };
    listenClipboardChanges().listen((clip) async {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(kMacHostUid)
          .collection('devices')
          .get();
      for (final doc in snap.docs) {
        if (doc.id != kMacDeviceId) {
          await relay.send(
            uid: kMacHostUid,
            senderId: kMacDeviceId,
            recipientId: doc.id,
            kind: RelayKind.clipboard,
            payload: {'text': clip.content},
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Splurter AirSync',
      debugShowCheckedModeBanner: false,
      theme: SplurterTheme.light,
      darkTheme: SplurterTheme.dark,
      themeMode: ThemeMode.dark,
      home: const DashboardShell(),
    );
  }
}

class DashboardShell extends ConsumerStatefulWidget {
  const DashboardShell({super.key});

  @override
  ConsumerState<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends ConsumerState<DashboardShell> {
  int _selectedTabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final isCompact = ref.watch(isCompactModeProvider);
    final pairingState = ref.watch(pairingStateProvider);
    final Device? pairedDevice = pairingState is PairingConnected ? pairingState.device : null;
    final history = ref.watch(clipHistoryProvider);
    final latestClip = history.isNotEmpty ? history.first.content : null;

    final hostUid = FirebaseAuth.instance.currentUser?.uid ?? kMacHostUid;
    final remoteDevicesAsync = ref.watch(remoteDevicesStreamProvider(hostUid));
    final remoteDevices = remoteDevicesAsync.asData?.value ?? [];

    final secondaryDevice = remoteDevices.firstWhere(
      (d) => d.platform != 'macos',
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

    if (remoteDevicesAsync.hasValue) {
      if (hasRemoteDevice && pairedDevice == null) {
        Future.microtask(() {
          ref.read(pairingStateProvider.notifier).complete(secondaryDevice);
        });
      } else if (!hasRemoteDevice && pairedDevice != null) {
        Future.microtask(() {
          ref.read(pairingStateProvider.notifier).unpair(uid: hostUid, deviceId: kMacDeviceId);
        });
      }
    }

    final activeDevice = (hasRemoteDevice && pairedDevice != null) ? pairedDevice : (hasRemoteDevice ? secondaryDevice : null);

    final invitationCode = PairingInvitation(
      version: RelayEnvelope.currentVersion,
      hostUid: hostUid,
      pairId: 'pair-mac-1',
      device: PairedDevice(
        id: kMacDeviceId,
        name: 'My Mac',
        platform: 'macos',
        publicKey: 'pubkey-mac-1',
        capabilities: {Capability.clipboard, Capability.fileTransfer, Capability.notifications},
        pairedAt: DateTime.now(),
      ),
      expiresAt: DateTime.now().add(const Duration(days: 365)),
    ).toCode();

    // 1. Compact Floating Phone Window Mode
    if (isCompact) {
      return Scaffold(
        backgroundColor: const Color(0xFF0B0F17),
        body: SafeArea(
          child: Column(
            children: [
              // Header bar for compact floating mode
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                color: Colors.black.withValues(alpha: 0.3),
                child: Row(
                  children: [
                    const Icon(Icons.phonelink, size: 16, color: Color(0xFF818CF8)),
                    const SizedBox(width: 8),
                    const Text(
                      'Splurter Float',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.open_in_full, size: 16, color: Colors.white70),
                      tooltip: 'Expand Dashboard',
                      onPressed: () {
                        ref.read(isCompactModeProvider.notifier).state = false;
                        setCompactWindowMode(false);
                      },
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: PhoneMockupWidget(
                    device: activeDevice,
                    latestClipboardText: latestClip,
                    width: 260,
                    height: 510,
                    onMirrorTap: () async {
                      if (activeDevice != null && activeDevice.address.isNotEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Launching screen mirror for ${activeDevice.name}...')),
                        );
                        await launchScreenMirroring(
                          ipAddress: activeDevice.address,
                          deviceName: activeDevice.name,
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('No active device connected for screen mirroring.')),
                        );
                      }
                    },
                    onCopyTap: () {
                      if (latestClip != null) {
                        writeClipboard(latestClip);
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 2. Full Glassmorphic macOS Dashboard Mode
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F17),
      body: Row(
        children: [
          // Left Sidebar Pane with Interactive Phone Frame (AirSync Style)
          Container(
            width: 295,
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A).withValues(alpha: 0.95),
              border: const Border(
                right: BorderSide(color: Color(0xFF1E293B), width: 1),
              ),
            ),
            child: Column(
              children: [
                const SizedBox(height: 28), // Space for window control traffic lights

                // Header Title & Floating Mode Toggle
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.phonelink_setup_rounded, color: Color(0xFF818CF8), size: 20),
                      ),
                      const SizedBox(width: 10),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'AirSync',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'macOS Continuity',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.picture_in_picture_alt, size: 18, color: Color(0xFF818CF8)),
                        tooltip: 'Pin Floating Phone Widget',
                        onPressed: () {
                          ref.read(isCompactModeProvider.notifier).state = true;
                          setCompactWindowMode(true);
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Physical Phone Frame Mockup Component
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        PhoneMockupWidget(
                          device: activeDevice,
                          latestClipboardText: latestClip,
                          width: 245,
                          height: 485,
                          onMirrorTap: () async {
                            if (activeDevice != null && activeDevice.address.isNotEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Launching screen mirror for ${activeDevice.name}...')),
                              );
                              await launchScreenMirroring(
                                ipAddress: activeDevice.address,
                                deviceName: activeDevice.name,
                              );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('No active device connected for screen mirroring.')),
                              );
                            }
                          },
                          onCopyTap: () {
                            if (latestClip != null) {
                              writeClipboard(latestClip);
                            }
                          },
                        ),
                        const SizedBox(height: 14),

                        // Action Buttons Bar under Phone Frame
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    ref.read(isCompactModeProvider.notifier).state = true;
                                    setCompactWindowMode(true);
                                  },
                                  icon: const Icon(Icons.aspect_ratio, size: 14),
                                  label: const Text('Float Phone', style: TextStyle(fontSize: 11)),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFFC7D2FE),
                                    side: const BorderSide(color: Color(0xFF4F46E5)),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Right Dashboard Content Area
          Expanded(
            child: Column(
              children: [
                const SizedBox(height: 28), // Titlebar padding

                // Top Navigation Bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: Color(0xFF1E293B), width: 1)),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _NavTabButton(
                          icon: Icons.devices_rounded,
                          label: 'Devices',
                          isSelected: _selectedTabIndex == 0,
                          onTap: () => setState(() => _selectedTabIndex = 0),
                        ),
                        const SizedBox(width: 6),
                        _NavTabButton(
                          icon: Icons.content_paste_rounded,
                          label: 'Clipboard',
                          isSelected: _selectedTabIndex == 1,
                          onTap: () => setState(() => _selectedTabIndex = 1),
                        ),
                        const SizedBox(width: 6),
                        _NavTabButton(
                          icon: Icons.swap_horiz_rounded,
                          label: 'Transfers',
                          isSelected: _selectedTabIndex == 2,
                          onTap: () => setState(() => _selectedTabIndex = 2),
                        ),
                        const SizedBox(width: 6),
                        _NavTabButton(
                          icon: Icons.settings_rounded,
                          label: 'Settings',
                          isSelected: _selectedTabIndex == 3,
                          onTap: () => setState(() => _selectedTabIndex = 3),
                        ),
                        if (activeDevice != null) ...[
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.check_circle, color: Colors.greenAccent, size: 12),
                                const SizedBox(width: 6),
                                Text(
                                  activeDevice.name,
                                  style: const TextStyle(
                                    color: Colors.greenAccent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // Dynamic Body View
                Expanded(
                  child: IndexedStack(
                    index: _selectedTabIndex,
                    children: [
                      _DevicesView(activeDevice: activeDevice, invitationCode: invitationCode),
                      const _ClipboardView(),
                      const _TransfersView(),
                      const _SettingsView(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavTabButton extends StatelessWidget {
  const _NavTabButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF6366F1).withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? const Color(0xFF6366F1).withValues(alpha: 0.5) : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? const Color(0xFF818CF8) : Colors.white60,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white60,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DevicesView extends ConsumerWidget {
  const _DevicesView({required this.activeDevice, required this.invitationCode});

  final Device? activeDevice;
  final String invitationCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (activeDevice == null) {
      return PairingScreen(pairingCode: invitationCode);
    }

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.greenAccent, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Connected to ${activeDevice!.name}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.greenAccent,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Always-On Native Continuity • Direct Local Wi-Fi & Firestore Cloud Relay',
                      style: TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  ref.read(relayLoopProvider).stop();
                  final hostUid = FirebaseAuth.instance.currentUser?.uid ?? kMacHostUid;
                  await ref.read(pairingStateProvider.notifier).unpair(uid: hostUid, deviceId: kMacDeviceId);
                },
                icon: const Icon(Icons.link_off, size: 16),
                label: const Text('Unpair Device'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent.withValues(alpha: 0.2),
                  foregroundColor: Colors.redAccent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        DeviceCard(device: activeDevice!),
      ],
    );
  }
}

class _ClipboardView extends ConsumerWidget {
  const _ClipboardView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(clipHistoryProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Clipboard Ring Buffer'),
        actions: [
          if (history.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
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
    final pairingState = ref.watch(pairingStateProvider);
    final activeDevice = pairingState is PairingConnected ? pairingState.device : null;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('File Transfers'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: ElevatedButton.icon(
              onPressed: () async {
                final file = await pickFile();
                if (file != null) {
                  final recipientId = activeDevice?.id ?? 'android-device-id';
                  await DirectFileStreamer.instance.sendFile(
                    filePath: file.path,
                    fileName: file.name,
                    fileSize: file.size,
                    uid: kMacHostUid,
                    senderId: kMacDeviceId,
                    recipientId: recipientId,
                    ref: ref,
                  );
                }
              },
              icon: const Icon(Icons.upload_file_rounded, size: 16),
              label: const Text('Send File'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
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
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Continuity Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            title: const Text('Universal Clipboard Sync'),
            subtitle: const Text('Automatically share NSPasteboard with paired Android device'),
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
