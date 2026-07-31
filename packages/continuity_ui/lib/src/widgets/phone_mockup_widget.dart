import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_types/shared_types.dart';

class PhoneMockupWidget extends StatefulWidget {
  const PhoneMockupWidget({
    super.key,
    required this.device,
    this.latestClipboardText,
    this.batteryLevel = 88,
    this.isCharging = false,
    this.onMirrorTap,
    this.onCopyTap,
    this.width = 240,
    this.height = 490,
  });

  final Device? device;
  final String? latestClipboardText;
  final int batteryLevel;
  final bool isCharging;
  final VoidCallback? onMirrorTap;
  final VoidCallback? onCopyTap;
  final double width;
  final double height;

  @override
  State<PhoneMockupWidget> createState() => _PhoneMockupWidgetState();
}

class _PhoneMockupWidgetState extends State<PhoneMockupWidget> {
  late Timer _clockTimer;
  DateTime _currentTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) {
        setState(() {
          _currentTime = DateTime.now();
        });
      }
    });
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    super.dispose();
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = widget.device != null && widget.device!.isPaired;
    final deviceName = widget.device?.name ?? 'Android Phone';

    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isConnected
              ? const Color(0xFF6366F1).withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.15),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: isConnected
                ? const Color(0xFF6366F1).withValues(alpha: 0.25)
                : Colors.black.withValues(alpha: 0.4),
            blurRadius: 24,
            spreadRadius: 2,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Stack(
          children: [
            // Wallpaper Background Gradient
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF1E1B4B),
                    Color(0xFF0F172A),
                    Color(0xFF0284C7),
                  ],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
              ),
            ),

            // Subtle Glass Overlay
            Container(
              color: Colors.black.withValues(alpha: 0.25),
            ),

            // Content Column
            Column(
              children: [
                // Top Punch-hole Notch & Status Bar Header
                Padding(
                  padding: const EdgeInsets.only(top: 8, left: 16, right: 16, bottom: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Time
                      Text(
                        _formatTime(_currentTime),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.3,
                        ),
                      ),

                      // Punch-hole camera notch
                      Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: Colors.black,
                          shape: BoxShape.circle,
                        ),
                      ),

                      // Battery & Wifi icons
                      Row(
                        children: [
                          const Icon(Icons.wifi, size: 13, color: Colors.white),
                          const SizedBox(width: 4),
                          Icon(
                            widget.isCharging ? Icons.battery_charging_full : Icons.battery_std,
                            size: 14,
                            color: Colors.greenAccent,
                          ),
                          Text(
                            ' ${widget.batteryLevel}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Device Branding Header Pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isConnected ? Icons.circle : Icons.circle_outlined,
                        size: 8,
                        color: isConnected ? Colors.greenAccent : Colors.amberAccent,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        deviceName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // Live Clipboard Card Preview Widget
                if (widget.latestClipboardText != null && widget.latestClipboardText!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B).withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.content_paste_go, size: 14, color: Color(0xFF818CF8)),
                              const SizedBox(width: 6),
                              const Text(
                                'Universal Clipboard',
                                style: TextStyle(
                                  color: Color(0xFFC7D2FE),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Spacer(),
                              InkWell(
                                onTap: widget.onCopyTap,
                                child: const Icon(Icons.copy, size: 14, color: Colors.white70),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            widget.latestClipboardText!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.phonelink_ring, size: 16, color: Colors.white60),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Seamless Continuity Active',
                              style: TextStyle(color: Colors.white70, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 14),

                // Interactive Mirror Screen Button Action
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: widget.onMirrorTap,
                      icon: const Icon(Icons.screen_share_rounded, size: 16),
                      label: const Text(
                        'Mirror Screen',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4F46E5),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ),

                const Spacer(),

                // Home Indicator Bar
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  width: 72,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
