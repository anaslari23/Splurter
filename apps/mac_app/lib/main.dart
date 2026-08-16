import 'dart:math' as math;
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

class PhoneNotificationData {
  const PhoneNotificationData({
    required this.appName,
    required this.title,
    required this.text,
    required this.time,
  });
  final String appName;
  final String title;
  final String text;
  final String time;
}

final latestPhoneNotificationProvider = StateProvider<PhoneNotificationData?>((ref) {
  return null;
});

final notificationHistoryProvider = StateProvider<List<PhoneNotificationData>>((ref) => []);
final isHistoryDrawerOpenProvider = StateProvider<bool>((ref) => false);
final syncActivityProvider = StateProvider<String?>((ref) => null);
final isSidebarCollapsedProvider = StateProvider<bool>((ref) => false);

bool _isIgnoredSystemNotif(String appName, String title) {
  final lowerApp = appName.toLowerCase();
  final lowerTitle = title.toLowerCase();
  if (lowerApp == 'system ui' || lowerApp == 'android system' || lowerApp == 'android' || lowerApp == 'settings') {
    return true;
  }
  if (lowerTitle.contains('adaptive charging') ||
      lowerTitle.contains('usb debugging') ||
      lowerTitle.contains('charging steadily') ||
      lowerTitle.contains('battery full by')) {
    return true;
  }
  return false;
}

void _triggerSyncToast(WidgetRef ref, String msg) {
  ref.read(syncActivityProvider.notifier).state = msg;
  Future.delayed(const Duration(seconds: 4), () {
    if (ref.read(syncActivityProvider) == msg) {
      ref.read(syncActivityProvider.notifier).state = null;
    }
  });
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

    final pairingState = ref.read(pairingStateProvider);
    if (pairingState is! PairingConnected) {
      for (final targetUid in {kMacHostUid, 'mac-channel-1'}) {
        try {
          final snap = await FirebaseFirestore.instance
              .collection('users')
              .doc(targetUid)
              .collection('devices')
              .get();
          for (final doc in snap.docs) {
            if (doc.id != kMacDeviceId && doc.data()['platform'] != 'macos') {
              await doc.reference.delete();
            }
          }
        } catch (_) {}
      }
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
      _triggerSyncToast(ref, 'Clipboard synced via local Wi-Fi');
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

    relay.onNotificationReceived = (payload) {
      final appName = payload['appName'] as String? ?? payload['packageName'] as String? ?? 'Android';
      final title = payload['title'] as String? ?? 'Notification';
      final text = payload['text'] as String? ?? '';
      if (_isIgnoredSystemNotif(appName, title)) return;
      final notif = PhoneNotificationData(
        appName: appName,
        title: title,
        text: text,
        time: 'now',
      );
      ref.read(latestPhoneNotificationProvider.notifier).state = notif;
      ref.read(notificationHistoryProvider.notifier).state = [
        notif,
        ...ref.read(notificationHistoryProvider),
      ];
      _triggerSyncToast(ref, 'Notification mirrored ($appName)');
    };

    for (final targetUid in {kMacHostUid, 'mac-channel-1'}) {
      FirebaseFirestore.instance
          .collection('users')
          .doc(targetUid)
          .collection('signals')
          .snapshots()
          .listen((snap) {
        for (final doc in snap.docChanges) {
          if (doc.type == DocumentChangeType.added) {
            final data = doc.doc.data();
            if (data != null && data['kind'] == 'notification') {
              final payload = data['payload'] as Map<String, dynamic>? ?? {};
              final appName = payload['appName'] as String? ?? payload['packageName'] as String? ?? 'Android';
              final title = payload['title'] as String? ?? 'Notification';
              final text = payload['text'] as String? ?? '';
              if (_isIgnoredSystemNotif(appName, title)) return;
              final notif = PhoneNotificationData(
                appName: appName,
                title: title,
                text: text,
                time: 'now',
              );
              ref.read(latestPhoneNotificationProvider.notifier).state = notif;
              ref.read(notificationHistoryProvider.notifier).state = [
                notif,
                ...ref.read(notificationHistoryProvider),
              ];
              _triggerSyncToast(ref, 'Cloud notification mirrored ($appName)');
            }
          }
        }
      });
    }
    _triggerSyncToast(ref, 'Connected to local Wi-Fi network');
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Splurter',
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
    final isSidebarCollapsed = ref.watch(isSidebarCollapsedProvider);
    final notifHistory = ref.watch(notificationHistoryProvider);
    final isHistoryDrawerOpen = ref.watch(isHistoryDrawerOpenProvider);
    final syncActivity = ref.watch(syncActivityProvider);
    final pairingState = ref.watch(pairingStateProvider);
    final Device? pairedDevice = pairingState is PairingConnected ? pairingState.device : null;
    final history = ref.watch(clipHistoryProvider);
    final latestClip = history.isNotEmpty ? history.first.content : null;
    final latestNotif = ref.watch(latestPhoneNotificationProvider);

    final hostUid = FirebaseAuth.instance.currentUser?.uid ?? kMacHostUid;
    final remoteDevicesAsync = ref.watch(remoteDevicesStreamProvider(hostUid));
    final fallbackDevicesAsync = ref.watch(remoteDevicesStreamProvider(kMacHostUid));
    final rawRemoteDevices = [
      ...?(remoteDevicesAsync.asData?.value),
      ...?(fallbackDevicesAsync.asData?.value),
    ];
    final seenKeys = <String>{};
    final remoteDevices = rawRemoteDevices.where((d) {
      final key = '${d.platform}_${d.name}_${d.address}';
      if (seenKeys.contains(key)) return false;
      seenKeys.add(key);
      return true;
    }).toList();

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

    if (hasRemoteDevice && pairedDevice == null) {
      Future.microtask(() {
        ref.read(pairingStateProvider.notifier).complete(secondaryDevice);
      });
    }

    final activeDevice = pairedDevice == null
        ? null
        : (hasRemoteDevice ? secondaryDevice.copyWith(isPaired: true) : pairedDevice);

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
                    notificationAppName: latestNotif?.appName,
                    notificationTitle: latestNotif?.title,
                    notificationText: latestNotif?.text,
                    notificationTime: latestNotif?.time,
                    onNotificationDismiss: () {
                      ref.read(latestPhoneNotificationProvider.notifier).state = null;
                    },
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
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            width: isSidebarCollapsed ? 0 : 270,
            clipBehavior: Clip.hardEdge,
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
                            'Splurter',
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
                          notificationAppName: latestNotif?.appName,
                          notificationTitle: latestNotif?.title,
                          notificationText: latestNotif?.text,
                          notificationTime: latestNotif?.time,
                          onNotificationDismiss: () {
                            ref.read(latestPhoneNotificationProvider.notifier).state = null;
                          },
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
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: math.max(
                          0.0,
                          MediaQuery.sizeOf(context).width - (isSidebarCollapsed ? 0 : 270) - 32,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              IconButton(
                                icon: Icon(
                                  isSidebarCollapsed ? Icons.menu_rounded : Icons.menu_open_rounded,
                                  color: Colors.white70,
                                  size: 18,
                                ),
                                tooltip: isSidebarCollapsed ? 'Show Sidebar' : 'Hide Sidebar',
                                onPressed: () => ref.read(isSidebarCollapsedProvider.notifier).state = !isSidebarCollapsed,
                              ),
                              const SizedBox(width: 8),
                              _NavTabButton(
                                icon: Icons.devices_rounded,
                                label: 'Devices',
                                isSelected: _selectedTabIndex == 0,
                                onTap: () => setState(() => _selectedTabIndex = 0),
                              ),
                              const SizedBox(width: 6),
                              _NavTabButton(
                                icon: Icons.settings_rounded,
                                label: 'Settings',
                                isSelected: _selectedTabIndex == 1,
                                onTap: () => setState(() => _selectedTabIndex = 1),
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
                              if (syncActivity != null) ...[
                                const SizedBox(width: 16),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981).withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.5)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.sync_rounded, color: Color(0xFF34D399), size: 14),
                                      const SizedBox(width: 6),
                                      Text(
                                        syncActivity,
                                        style: const TextStyle(
                                          color: Color(0xFF34D399),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                          Row(
                            children: [
                              IconButton(
                                icon: Badge(
                                  isLabelVisible: notifHistory.isNotEmpty,
                                  label: Text('${notifHistory.length}', style: const TextStyle(fontSize: 10)),
                                  child: Icon(
                                    Icons.notifications_rounded,
                                    color: isHistoryDrawerOpen ? const Color(0xFF818CF8) : Colors.white70,
                                    size: 18,
                                  ),
                                ),
                                tooltip: 'Notification History',
                                onPressed: () => ref.read(isHistoryDrawerOpenProvider.notifier).state = !isHistoryDrawerOpen,
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.aspect_ratio_rounded, color: Colors.white70, size: 18),
                                tooltip: 'Float Compact Mode',
                                onPressed: () => ref.read(isCompactModeProvider.notifier).state = true,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Dynamic Body View
                Expanded(
                  child: Stack(
                    children: [
                      IndexedStack(
                        index: _selectedTabIndex,
                        children: [
                          _DevicesView(
                            activeDevice: activeDevice,
                            invitationCode: invitationCode,
                            discoveredDevices: remoteDevices,
                          ),
                          const _SettingsView(),
                        ],
                      ),
                      if (isHistoryDrawerOpen)
                        Positioned(
                          top: 0,
                          right: 0,
                          bottom: 0,
                          child: _NotificationHistoryDrawer(
                            history: notifHistory,
                            onClose: () => ref.read(isHistoryDrawerOpenProvider.notifier).state = false,
                            onClear: () => ref.read(notificationHistoryProvider.notifier).state = [],
                          ),
                        ),
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
  const _DevicesView({
    required this.activeDevice,
    required this.invitationCode,
    required this.discoveredDevices,
  });

  final Device? activeDevice;
  final String invitationCode;
  final List<Device> discoveredDevices;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (activeDevice == null) {
      return PairingScreen(
        pairingCode: invitationCode,
        discoveredDevices: discoveredDevices,
        onDeviceSelected: (dev) => ref.read(pairingStateProvider.notifier).complete(dev),
      );
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
                    const SizedBox(height: 4),
                    const Text(
                      'Always-On Continuity Active • Universal Clipboard',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Copy anywhere on this Mac to paste on your Android, and vice versa—completely in the background.',
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

class _NotificationHistoryDrawer extends StatelessWidget {
  const _NotificationHistoryDrawer({
    required this.history,
    required this.onClose,
    required this.onClear,
  });

  final List<PhoneNotificationData> history;
  final VoidCallback onClose;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: 0.98),
        border: const Border(left: BorderSide(color: Color(0xFF1E293B))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(-4, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
            ),
            child: Row(
              children: [
                const Icon(Icons.history_rounded, color: Color(0xFF818CF8), size: 18),
                const SizedBox(width: 8),
                const Text(
                  'Notification History',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const Spacer(),
                if (history.isNotEmpty)
                  TextButton(
                    onPressed: onClear,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Clear all', style: TextStyle(color: Colors.white54, fontSize: 11)),
                  ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Close',
                  onPressed: onClose,
                ),
              ],
            ),
          ),
          Expanded(
            child: history.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.notifications_none_rounded, color: Colors.white24, size: 40),
                          SizedBox(height: 12),
                          Text('No notifications', style: TextStyle(color: Colors.white60, fontSize: 13, fontWeight: FontWeight.w600)),
                          SizedBox(height: 8),
                          Text(
                            'To mirror phone notifications, ensure Notification Access permission is enabled in your Splurter Android app.',
                            style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.3),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: history.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final item = history[index];
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B).withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    item.appName,
                                    style: const TextStyle(
                                      color: Color(0xFF818CF8),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  item.time,
                                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              item.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            if (item.text.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                item.text,
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
