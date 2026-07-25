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
  });

  final String? pairingCode;
  final ValueChanged<String>? onCodeSubmitted;
  final ValueGetter<Device>? onPaired;

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
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: QrImageView(
                    data: widget.pairingCode!,
                    version: QrVersions.auto,
                    size: 200.0,
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
            ],
          ),
        ),
      ),
    );
  }
}

