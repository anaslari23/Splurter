import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    this.id,
    required this.appName,
    required this.title,
    required this.text,
    required this.time,
    this.canReply = false,
  });
  final String? id;
  final String appName;
  final String title;
  final String text;
  final String time;
  final bool canReply;
}

final latestPhoneNotificationProvider = StateProvider<PhoneNotificationData?>((ref) {
  return null;
});

/// Tracks *currently active* live notifications (session-only, cleared on disconnect).
/// We use a LinkedHashMap-style approach: keyed by notification ID so updates
/// replace duplicates in-place. The list order reflects arrival order.
final notificationHistoryProvider = StateProvider<List<PhoneNotificationData>>((ref) => []);
final isHistoryDrawerOpenProvider = StateProvider<bool>((ref) => false);
final syncActivityProvider = StateProvider<String?>((ref) => null);
final isSidebarCollapsedProvider = StateProvider<bool>((ref) => false);

/// Timestamp captured at boot — any Firestore signal older than this is historical
/// and must be ignored so we never replay past notifications on app restart.
DateTime _startedAt = DateTime.now();

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

void _addNotification(WidgetRef ref, PhoneNotificationData notif) {
  final current = ref.read(notificationHistoryProvider);
  // Deduplicate: if same ID already exists, replace it in-place
  if (notif.id != null && current.any((n) => n.id == notif.id)) {
    ref.read(notificationHistoryProvider.notifier).state =
        current.map((n) => n.id == notif.id ? notif : n).toList();
  } else {
    ref.read(notificationHistoryProvider.notifier).state = [notif, ...current];
  }
}

void _triggerSyncToast(WidgetRef ref, String msg) {
  ref.read(syncActivityProvider.notifier).state = msg;
  Future.delayed(const Duration(seconds: 4), () {
    if (ref.read(syncActivityProvider) == msg) {
      ref.read(syncActivityProvider.notifier).state = null;
    }
  });
}

/// Last device ID we pushed to the Swift menu bar, to avoid redundant calls.
String? _lastPushedDeviceId;

/// Pushes the active device's IP + name to Swift (for the menu-bar Mirror button)
/// and clears stale notifications when the device disconnects.
void _syncDeviceToMenuBar(WidgetRef ref, Device? activeDevice) {
  if (activeDevice?.id == _lastPushedDeviceId) return; // nothing changed
  _lastPushedDeviceId = activeDevice?.id;

  if (activeDevice != null && activeDevice.address.isNotEmpty) {
    // Device connected — tell Swift so the Mirror menu item can work instantly.
    final ch = MethodChannel('splurter/network');
    ch.invokeMethod('setPairedDevice', {
      'ipAddress': activeDevice.address,
      'deviceName': activeDevice.name,
    }).ignore();
  } else {
    // Device disconnected — clear its IP from Swift and wipe stale notifications.
    final ch = MethodChannel('splurter/network');
    ch.invokeMethod('setPairedDevice', {
      'ipAddress': '',
      'deviceName': '',
    }).ignore();
    // Clear notifications so we start fresh when paired again.
    ref.read(notificationHistoryProvider.notifier).state = [];
    ref.read(latestPhoneNotificationProvider.notifier).state = null;
  }
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
    // Capture boot time — Firestore signals older than this are historical
    // (the listener re-delivers them as 'added' on first attach) and must be ignored.
    _startedAt = DateTime.now();

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
      final action = payload['action'] as String? ?? 'post';
      final id = payload['id'] as String?;

      // Guard: ignore signals that were created before we booted (history replay)
      final createdAtMs = payload['createdAt'] as int?;
      if (createdAtMs != null) {
        final createdAt = DateTime.fromMillisecondsSinceEpoch(createdAtMs);
        if (createdAt.isBefore(_startedAt)) return;
      }

      if (action == 'remove') {
        if (id != null) {
          final history = ref.read(notificationHistoryProvider);
          ref.read(notificationHistoryProvider.notifier).state = history.where((n) => n.id != id).toList();
          final current = ref.read(latestPhoneNotificationProvider);
          if (current?.id == id) {
            ref.read(latestPhoneNotificationProvider.notifier).state = null;
          }
        }
        return;
      }

      final appName = payload['appName'] as String? ?? payload['packageName'] as String? ?? 'Android';
      final title = payload['title'] as String? ?? 'Notification';
      final text = payload['text'] as String? ?? '';
      final canReply = payload['canReply'] as bool? ?? false;
      if (_isIgnoredSystemNotif(appName, title)) return;
      final notif = PhoneNotificationData(
        id: id,
        appName: appName,
        title: title,
        text: text,
        time: 'now',
        canReply: canReply,
      );
      ref.read(latestPhoneNotificationProvider.notifier).state = notif;
      _addNotification(ref, notif);
      _triggerSyncToast(ref, 'Notification from $appName');
    };

    // NOTE: The relay already listens to Firestore signals internally.
    // We do NOT attach a second manual Firestore listener here — that caused
    // every notification to be processed twice and history to be replayed on startup.

    // ── Incoming call: show native macOS notification + in-app banner ──
    const _notifChannel = MethodChannel('splurter/native_notifications');
    _notifChannel.setMethodCallHandler((call) async {
      if (call.method == 'onCallAction') {
        final args = call.arguments as Map?;
        final action = args?['action'] as String? ?? '';
        final callId = args?['callId'] as String? ?? '';
        final currentCall = ref.read(activeCallProvider);
        final hostUid = FirebaseAuth.instance.currentUser?.uid ?? kMacHostUid;
        final pairingState = ref.read(pairingStateProvider);
        final targetId = pairingState is PairingConnected ? pairingState.device.id : 'android-device-id';

        if (action == 'answer') {
          await ref.read(relayLoopProvider).answerPhoneCall(
            uid: hostUid, senderId: kMacDeviceId, recipientId: targetId,
          );
          if (currentCall != null) {
            ref.read(activeCallProvider.notifier).state = PhoneCallEvent(
              callId: currentCall.callId,
              number: currentCall.number,
              callerName: currentCall.callerName,
              state: 'offhook',
              timestamp: DateTime.now(),
            );
          }
          _triggerSyncToast(ref, 'Call answered on Android');
        } else if (action == 'decline') {
          await ref.read(relayLoopProvider).endPhoneCall(
            uid: hostUid, senderId: kMacDeviceId, recipientId: targetId,
          );
          ref.read(activeCallProvider.notifier).state = null;
          _triggerSyncToast(ref, 'Call declined');
        }
      }
    });

    relay.onCallReceived = (call) async {
      if (call.state == 'idle') {
        // Call ended — dismiss native notification and in-app banner
        ref.read(activeCallProvider.notifier).state = null;
        try {
          await _notifChannel.invokeMethod('dismissCall', {'callId': call.callId});
        } catch (_) {}
      } else if (call.state == 'ringing') {
        // New incoming call — update in-app banner AND fire native call notification
        ref.read(activeCallProvider.notifier).state = call;
        try {
          await _notifChannel.invokeMethod('showCall', {
            'callId': call.callId,
            'callerName': call.callerName,
            'number': call.number,
          });
        } catch (_) {}
      } else {
        // offhook / other states — update banner only
        ref.read(activeCallProvider.notifier).state = call;
      }
    };

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


  @override
  Widget build(BuildContext context) {
    final isCompact = ref.watch(isCompactModeProvider);
    final notifHistory = ref.watch(notificationHistoryProvider);
    final syncActivity = ref.watch(syncActivityProvider);
    final pairingState = ref.watch(pairingStateProvider);
    final Device? pairedDevice = pairingState is PairingConnected ? pairingState.device : null;
    final history = ref.watch(clipHistoryProvider);
    final latestClip = history.isNotEmpty ? history.first.content : null;
    final latestNotif = ref.watch(latestPhoneNotificationProvider);
    final activeCall = ref.watch(activeCallProvider);

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

    // When a device connects, push its IP to Swift so the menu-bar Mirror button works.
    // When it disconnects, clear stale notifications from the previous session.
    _syncDeviceToMenuBar(ref, activeDevice);

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

    // 2. Minimal single-column window — no sidebar, no feature cards
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F17),
      body: Column(
        children: [
          const SizedBox(height: 28), // macOS traffic lights

          // ── Slim top bar ──────────────────────────────────────────────
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF1E293B), width: 1)),
            ),
            child: Row(
              children: [
                // App wordmark
                const Icon(Icons.phonelink_setup_rounded, color: Color(0xFF818CF8), size: 16),
                const SizedBox(width: 8),
                const Text(
                  'Splurter',
                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 12),
                // Connected device chip
                if (activeDevice != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.circle, color: Color(0xFF34D399), size: 6),
                        const SizedBox(width: 5),
                        Text(
                          activeDevice.name,
                          style: const TextStyle(color: Color(0xFF34D399), fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                // Sync toast
                if (syncActivity != null) ...[
                  const SizedBox(width: 10),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.sync_rounded, color: Color(0xFF34D399), size: 12),
                      const SizedBox(width: 4),
                      Text(syncActivity, style: const TextStyle(color: Color(0xFF34D399), fontSize: 11)),
                    ],
                  ),
                ],
                const Spacer(),
                // Notification count badge
                if (notifHistory.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.notifications_rounded, color: Color(0xFF818CF8), size: 12),
                        const SizedBox(width: 4),
                        Text(
                          '${notifHistory.length}',
                          style: const TextStyle(color: Color(0xFF818CF8), fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // ── Body ──────────────────────────────────────────────────────
          Expanded(
            child: Stack(
              children: [
                _DevicesView(
                  activeDevice: activeDevice,
                  invitationCode: invitationCode,
                  discoveredDevices: remoteDevices,
                  notifHistory: notifHistory,
                ),
                // Incoming call banner floats over content
                if (activeCall != null)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: IncomingCallBanner(
                      call: activeCall,
                      onAnswer: () async {
                        final hostUid = FirebaseAuth.instance.currentUser?.uid ?? kMacHostUid;
                        final targetId = activeDevice?.id ?? 'android-device-id';
                        await ref.read(relayLoopProvider).answerPhoneCall(
                              uid: hostUid,
                              senderId: kMacDeviceId,
                              recipientId: targetId,
                            );
                        ref.read(activeCallProvider.notifier).state = PhoneCallEvent(
                          callId: activeCall.callId,
                          number: activeCall.number,
                          callerName: activeCall.callerName,
                          state: 'offhook',
                          timestamp: DateTime.now(),
                        );
                        _triggerSyncToast(ref, 'Call answered on Android');
                      },
                      onDecline: () async {
                        final hostUid = FirebaseAuth.instance.currentUser?.uid ?? kMacHostUid;
                        final targetId = activeDevice?.id ?? 'android-device-id';
                        await ref.read(relayLoopProvider).endPhoneCall(
                              uid: hostUid,
                              senderId: kMacDeviceId,
                              recipientId: targetId,
                            );
                        ref.read(activeCallProvider.notifier).state = null;
                        _triggerSyncToast(ref, 'Call declined');
                      },
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
    required this.notifHistory,
  });

  final Device? activeDevice;
  final String invitationCode;
  final List<Device> discoveredDevices;
  final List<PhoneNotificationData> notifHistory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ── No device: show pairing QR ────────────────────────────────────
    if (activeDevice == null) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
          child: ContinuityPairingCard(
            pairingCode: invitationCode,
            onManualCodeSubmitted: (code) async {
              try {
                final invitation = PairingInvitation.fromCode(code);
                final device = Device(
                  id: invitation.device.id,
                  name: invitation.device.name,
                  platform: invitation.device.platform,
                  address: invitation.hostUid,
                  port: 9876,
                  version: '1.0',
                  capabilities: invitation.device.capabilities.map((c) => c.name).toList(),
                  isPaired: true,
                );
                ref.read(pairingStateProvider.notifier).complete(device);
              } catch (_) {}
            },
          ),
        ),
      );
    }

    // ── Device connected: compact status + live notifications ─────────
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      children: [
        // ── Compact device row ────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF1E293B)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF4F46E5)]),
                ),
                child: const Icon(Icons.phone_android_rounded, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      activeDevice!.name,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      children: [
                        _MetricBadge(
                          icon: activeDevice!.isCharging ? Icons.battery_charging_full_rounded : Icons.battery_std_rounded,
                          label: '${activeDevice!.batteryLevel}%',
                          color: activeDevice!.isCharging ? const Color(0xFF34D399) : const Color(0xFF818CF8),
                        ),
                        _MetricBadge(
                          icon: Icons.cell_tower_rounded,
                          label: activeDevice!.carrier,
                          color: const Color(0xFFA78BFA),
                        ),
                        _MetricBadge(
                          icon: Icons.wifi_tethering_rounded,
                          label: activeDevice!.address.isNotEmpty && activeDevice!.address != 'relay'
                              ? 'LAN Direct'
                              : 'Cloud Relay',
                          color: const Color(0xFF38BDF8),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Unpair — only action needed in window; Mirror is in menu bar
              TextButton.icon(
                onPressed: () async {
                  ref.read(relayLoopProvider).stop();
                  final hostUid = FirebaseAuth.instance.currentUser?.uid ?? kMacHostUid;
                  await ref.read(pairingStateProvider.notifier).unpair(uid: hostUid, deviceId: kMacDeviceId);
                },
                icon: const Icon(Icons.link_off_rounded, size: 14, color: Color(0xFFF87171)),
                label: const Text('Unpair', style: TextStyle(color: Color(0xFFF87171), fontSize: 12)),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ── Active Notifications ──────────────────────────────────────
        Row(
          children: [
            const Text(
              'Active Notifications',
              style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5),
            ),
            if (notifHistory.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${notifHistory.length}',
                  style: const TextStyle(color: Color(0xFF818CF8), fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => ref.read(notificationHistoryProvider.notifier).state = [],
                child: const Text('Clear all', style: TextStyle(color: Colors.white38, fontSize: 11)),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),

        if (notifHistory.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 32),
            alignment: Alignment.center,
            child: const Text(
              'No active notifications',
              style: TextStyle(color: Colors.white24, fontSize: 13),
            ),
          )
        else
          ...notifHistory.map((n) => _NotifRow(notif: n)),
      ],
    );
  }
}

/// A single compact notification row.
class _NotifRow extends ConsumerWidget {
  const _NotifRow({required this.notif});
  final PhoneNotificationData notif;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // App initial avatar
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              (notif.appName?.isNotEmpty == true ? notif.appName![0] : '?').toUpperCase(),
              style: const TextStyle(color: Color(0xFF818CF8), fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      notif.appName ?? 'Unknown',
                      style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    if (notif.time != null)
                      Text(
                        notif.time!,
                        style: const TextStyle(color: Colors.white24, fontSize: 10),
                      ),
                  ],
                ),
                if (notif.title != null && notif.title!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    notif.title!,
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (notif.text != null && notif.text!.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    notif.text!,
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          // Dismiss
          GestureDetector(
            onTap: () {
              final current = ref.read(notificationHistoryProvider);
              ref.read(notificationHistoryProvider.notifier).state =
                  current.where((n) => n.id != notif.id).toList();
            },
            child: const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(Icons.close_rounded, size: 14, color: Colors.white24),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricBadge extends StatelessWidget {
  const _MetricBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ContinuityFeatureCard extends StatelessWidget {
  const _ContinuityFeatureCard({
    required this.icon,
    required this.title,
    required this.status,
    required this.description,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String status;
  final String description;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF131C2E).withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      status,
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 11,
                    height: 1.3,
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



class _NotificationHistoryDrawer extends ConsumerWidget {
  const _NotificationHistoryDrawer({
    required this.history,
    required this.onClose,
    required this.onClear,
  });

  final List<PhoneNotificationData> history;
  final VoidCallback onClose;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                  'Active Notifications',
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
                      return _NotificationItemTile(
                        item: item,
                        onDismiss: () {
                          final id = item.id;
                          if (id != null) {
                            dismissAndroidNotification(id).ignore();
                            final relay = RelayLoop.instance;
                            final uid = relay.currentUid ?? kMacHostUid;
                            relay.dismissNotification(
                              uid: uid,
                              senderId: kMacDeviceId,
                              recipientId: 'android-device-id',
                              notifId: id,
                            ).ignore();
                          }
                          final currentHistory = ref.read(notificationHistoryProvider);
                          ref.read(notificationHistoryProvider.notifier).state =
                              currentHistory.where((n) => n != item).toList();
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _NotificationItemTile extends StatefulWidget {
  const _NotificationItemTile({
    required this.item,
    required this.onDismiss,
  });

  final PhoneNotificationData item;
  final VoidCallback onDismiss;

  @override
  State<_NotificationItemTile> createState() => _NotificationItemTileState();
}

class _NotificationItemTileState extends State<_NotificationItemTile> {
  bool _isReplying = false;
  bool _isSending = false;
  bool _isSent = false;
  final _replyController = TextEditingController();

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  Future<void> _sendReply() async {
    final text = _replyController.text.trim();
    if (text.isEmpty || widget.item.id == null) return;
    setState(() {
      _isSending = true;
    });

    final relay = RelayLoop.instance;
    final uid = relay.currentUid ?? kMacHostUid;
    await relay.replyToNotification(
      uid: uid,
      senderId: kMacDeviceId,
      recipientId: 'android-device-id',
      notifId: widget.item.id!,
      text: text,
    );

    if (mounted) {
      setState(() {
        _isSending = false;
        _isSent = true;
      });
      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) {
        setState(() {
          _isReplying = false;
          _isSent = false;
          _replyController.clear();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
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
                  widget.item.appName,
                  style: const TextStyle(
                    color: Color(0xFF818CF8),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                widget.item.time,
                style: const TextStyle(color: Colors.white38, fontSize: 10),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white38, size: 14),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Dismiss on Android',
                onPressed: widget.onDismiss,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            widget.item.title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          if (widget.item.text.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              widget.item.text,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
          if (widget.item.canReply) ...[
            const SizedBox(height: 8),
            if (!_isReplying)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => setState(() => _isReplying = true),
                  icon: const Icon(Icons.reply_rounded, size: 14, color: Color(0xFF38BDF8)),
                  label: const Text(
                    'Quick Reply',
                    style: TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    backgroundColor: const Color(0xFF38BDF8).withValues(alpha: 0.1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              )
            else
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _replyController,
                        autofocus: true,
                        enabled: !_isSending && !_isSent,
                        onSubmitted: (_) => _sendReply(),
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                        decoration: InputDecoration(
                          hintText: _isSent ? 'Reply sent ✓' : 'Type reply to ${widget.item.appName}...',
                          hintStyle: TextStyle(
                            color: _isSent ? const Color(0xFF4ADE80) : Colors.white38,
                            fontSize: 12,
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 4),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    if (_isSending)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF38BDF8)),
                      )
                    else if (_isSent)
                      const Icon(Icons.check_circle_rounded, color: Color(0xFF4ADE80), size: 16)
                    else ...[
                      IconButton(
                        icon: const Icon(Icons.send_rounded, color: Color(0xFF38BDF8), size: 16),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Send Reply',
                        onPressed: _sendReply,
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white38, size: 14),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Cancel',
                        onPressed: () => setState(() => _isReplying = false),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
