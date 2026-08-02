import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_types/shared_types.dart';

class PairingScreen extends ConsumerStatefulWidget {
  const PairingScreen({
    super.key,
    this.pairingCode,
    this.onCodeSubmitted,
    this.onPaired,
    this.discoveredDevices,
    this.onDeviceSelected,
  });

  final String? pairingCode;
  final ValueChanged<String>? onCodeSubmitted;
  final ValueGetter<Device>? onPaired;
  final List<Device>? discoveredDevices;
  final ValueChanged<Device>? onDeviceSelected;

  @override
  ConsumerState<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends ConsumerState<PairingScreen> {
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Pair Device')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              if (widget.pairingCode != null && widget.pairingCode!.isNotEmpty) ...[
                Text(
                  'Scan QR Code with Android Phone',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                Container(
                  width: 232,
                  height: 232,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: SizedBox(
                    width: 200,
                    height: 200,
                    child: QrImageView(
                      data: widget.pairingCode!,
                      version: QrVersions.auto,
                      size: 200.0,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Open Splurter on Android and tap "Scan QR Code"',
                  style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
              ] else ...[
                Icon(
                  Icons.qr_code_scanner,
                  size: 64,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Enter Pairing Invitation Code',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _codeController,
                  decoration: const InputDecoration(
                    labelText: 'Pairing Code',
                    hintText: 'Paste code from Mac here',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    final text = _codeController.text.trim();
                    if (text.isNotEmpty) {
                      widget.onCodeSubmitted?.call(text);
                    }
                  },
                  child: const Text('Connect & Pair'),
                ),
              ],
              if (widget.discoveredDevices != null && widget.discoveredDevices!.isNotEmpty) ...[
                const SizedBox(height: 32),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B).withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.wifi_tethering_rounded, color: Color(0xFF818CF8), size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'Available Devices on Local Network',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ...widget.discoveredDevices!.map((dev) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              dev.platform == 'macos' ? Icons.laptop_mac_rounded : Icons.phone_android_rounded,
                              color: const Color(0xFF38BDF8),
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    dev.name.isNotEmpty ? dev.name : 'Splurter (${dev.platform})',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 14),
                                  ),
                                  Text(
                                    dev.address.isNotEmpty ? 'IP: ${dev.address}' : 'Ready to pair via Wi-Fi',
                                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            FilledButton(
                              onPressed: () => widget.onDeviceSelected?.call(dev),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF6366F1),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text('Connect Instantly', style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                      )),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

