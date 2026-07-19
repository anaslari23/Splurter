import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PairingScreen extends ConsumerStatefulWidget {
  const PairingScreen({super.key});

  @override
  ConsumerState<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends ConsumerState<PairingScreen> {
  bool _scanning = true;
  bool _isPairing = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Pair Device')),
      body: _isPairing
          ? _buildPairingProgress(theme)
          : _scanning
              ? _buildScanner(theme)
              : _buildWelcome(theme),
    );
  }

  Widget _buildWelcome(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.link,
              size: 80,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 32),
            Text(
              'Connect to your devices',
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Scan a pairing QR code from another Splurter device to start sharing clipboard, files, and more.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 48),
            FilledButton.icon(
              onPressed: () => setState(() => _scanning = true),
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan QR Code'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _startHostPairing,
              icon: const Icon(Icons.qr_code),
              label: const Text('Show my pairing code'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanner(ThemeData theme) {
    return Column(
      children: [
        Expanded(
          child: MobileScanner(
            onDetect: (capture) async {
              if (_isPairing) return;
              final barcode = capture.barcodes.firstOrNull;
              if (barcode != null && barcode.rawValue != null) {
                await _processPairingCode(barcode.rawValue!);
              }
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              if (_error != null)
                Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                'Point the camera at the QR code on your other device',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: () => setState(() {
                  _scanning = false;
                  _error = null;
                }),
                child: const Text('Back'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPairingProgress(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text('Pairing in progress...', style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }

  Future<void> _processPairingCode(String code) async {
    setState(() {
      _error = null;
      _isPairing = true;
    });

    // TODO: Decode the QR, extract device info + fingerprint, prompt
    // the user to confirm, exchange keys, store the pairing.
    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      setState(() {
        _isPairing = false;
        _scanning = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pairing successful (placeholder)')),
      );
    }
  }

  Future<void> _startHostPairing() async {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('QR generation coming soon')),
      );
    }
  }
}
