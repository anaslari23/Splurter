import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:continuity_core/continuity_core.dart';
import 'package:continuity_state/continuity_state.dart';
import 'package:shared_types/shared_types.dart';
import '../../main.dart';

class QrScannerScreen extends ConsumerStatefulWidget {
  const QrScannerScreen({super.key});

  @override
  ConsumerState<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends ConsumerState<QrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _isProcessing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;
    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      final code = barcode.rawValue;
      if (code != null && code.isNotEmpty) {
        setState(() => _isProcessing = true);
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
            fingerprint: invitation.device.publicKey,
          );

          // Switch the relay to the Mac's host UID so this device reads signals
          if (invitation.hostUid.isNotEmpty) {
            ref.read(relayLoopProvider).switchUid(invitation.hostUid, deviceId: kAndroidDeviceId);

            // Register this Android device under the Mac's host UID so the Mac
            // recognizes it instantly in its real-time stream.
            await registerDevice(
              uid: invitation.hostUid,
              deviceId: kAndroidDeviceId,
              platform: 'android',
              name: 'Android Device',
            );
          }

          await ref.read(pairingStateProvider.notifier).complete(device);


          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Successfully paired with ${device.name}')),
            );
            context.pop();
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Invalid pairing code: $e')),
            );
            setState(() => _isProcessing = false);
          }
        }
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Mac QR Code'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      'Pairing device...',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
