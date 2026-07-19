import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_types/shared_types.dart';

class PairingScreen extends ConsumerStatefulWidget {
  const PairingScreen({super.key, this.onPaired});

  final ValueGetter<Device>? onPaired;

  @override
  ConsumerState<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends ConsumerState<PairingScreen> {
  bool _isPairing = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Pair Device')),
      body: SafeArea(
        child: _isPairing
            ? _buildPairingProgress(theme)
            : _buildWelcome(theme),
      ),
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
            const Text(
              'QR scanning is available on the Android app.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPairingProgress(ThemeData theme) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 24),
          Text('Pairing in progress...'),
        ],
      ),
    );
  }
}
