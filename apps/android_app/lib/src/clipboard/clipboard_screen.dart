import 'dart:async';

import 'package:flutter/material.dart';
import 'package:platform_bindings/platform_bindings.dart';

/// Android does not permit background clipboard capture. This is the explicit,
/// user-visible source of text sent to a paired Mac.
class ClipboardScreen extends StatefulWidget {
  const ClipboardScreen({super.key});

  @override
  State<ClipboardScreen> createState() => _ClipboardScreenState();
}

class _ClipboardScreenState extends State<ClipboardScreen> {
  final _controller = TextEditingController();
  StreamSubscription<ClipboardData>? _subscription;
  StreamSubscription<String>? _shareSubscription;
  String _status = 'Tap refresh to read your clipboard.';

  @override
  void initState() {
    super.initState();
    _subscription = listenClipboardChanges().listen((data) {
      if (!mounted) return;
      setState(() {
        _controller.text = data.content;
        _status = 'Clipboard changed in Splurter.';
      });
    });
    _shareSubscription = sharedText().listen((text) {
      if (!mounted) return;
      setState(() {
        _controller.text = text;
        _status = 'Text received from Android Share.';
      });
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _shareSubscription?.cancel();
    stopListeningClipboardChanges();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Clipboard')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Send text to your paired Mac', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text('Android only exposes clipboard data while Splurter is visible. Use this screen or Android Share to send copied text.'),
              const SizedBox(height: 16),
              Expanded(
                child: TextField(
                  controller: _controller,
                  expands: true,
                  minLines: null,
                  maxLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Clipboard text'),
                ),
              ),
              const SizedBox(height: 12),
              Text(_status),
              const SizedBox(height: 12),
              Row(
                children: [
                  OutlinedButton.icon(onPressed: _readClipboard, icon: const Icon(Icons.refresh), label: const Text('Refresh')),
                  const SizedBox(width: 12),
                  FilledButton.icon(onPressed: _copyLocally, icon: const Icon(Icons.content_copy), label: const Text('Copy locally')),
                ],
              ),
            ],
          ),
        ),
      );

  Future<void> _readClipboard() async {
    try {
      final data = await readClipboard();
      if (mounted) setState(() { _controller.text = data.content; _status = 'Clipboard loaded. Connect a paired Mac to send it.'; });
    } catch (_) {
      if (mounted) setState(() => _status = 'Clipboard is unavailable until Splurter is visible.');
    }
  }

  Future<void> _copyLocally() async {
    await writeClipboard(_controller.text);
    if (mounted) setState(() => _status = 'Copied locally.');
  }
}
