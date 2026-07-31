import 'package:flutter/material.dart';
import 'package:platform_bindings/platform_bindings.dart';

class AndroidPermissionBanner extends StatefulWidget {
  const AndroidPermissionBanner({super.key});

  @override
  State<AndroidPermissionBanner> createState() => _AndroidPermissionBannerState();
}

class _AndroidPermissionBannerState extends State<AndroidPermissionBanner> {
  AndroidPermissionStatus? _status;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final status = await getAndroidPermissionStatus();
    if (mounted) setState(() => _status = status);
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    if (status == null || status.allGranted) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.all(16),
      color: Colors.amber.shade900.withValues(alpha: 0.15),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.amber.shade600, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.shield_outlined, color: Colors.amber.shade400, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Permissions Required for Continuity',
                    style: TextStyle(
                      color: Colors.amber.shade200,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18, color: Colors.white70),
                  onPressed: _refresh,
                  tooltip: 'Refresh Status',
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'To enable background clipboard sync, notification mirroring, and direct LAN transfers, please enable these permissions:',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 12),
            if (!status.notificationAccess)
              _PermissionTile(
                title: 'Notification Access',
                subtitle: 'Mirrors Android notifications on your Mac',
                icon: Icons.notifications_active_outlined,
                onPressed: () async {
                  await openNotificationListenerSettings();
                  _refresh();
                },
                buttonText: 'Enable Access',
              ),
            if (!status.imeEnabled && !status.imeSelected)
              _PermissionTile(
                title: 'Splurter Keyboard Service',
                subtitle: 'Enables background cross-device clipboard sync',
                icon: Icons.keyboard_outlined,
                onPressed: () async {
                  await openInputMethodSettings();
                  await showInputMethodPicker();
                  _refresh();
                },
                buttonText: 'Enable Keyboard',
              ),
            if (!status.batteryExempt)
              _PermissionTile(
                title: 'Unrestricted Battery',
                subtitle: 'Prevents Android from stopping background sync',
                icon: Icons.battery_charging_full_outlined,
                onPressed: () async {
                  await requestBatteryExemption();
                  _refresh();
                },
                buttonText: 'Allow Unrestricted',
              ),
          ],
        ),
      ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  const _PermissionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onPressed,
    required this.buttonText,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onPressed;
  final String buttonText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.amber.shade300),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber.shade700,
              foregroundColor: Colors.black,
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(buttonText, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
