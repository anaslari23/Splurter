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
    this.carrier = '5G',
    this.nowPlayingTitle,
    this.nowPlayingArtist,
    this.notificationAppName,
    this.notificationTitle,
    this.notificationText,
    this.notificationTime,
    this.onMirrorTap,
    this.onCopyTap,
    this.onNotificationTap,
    this.onNotificationDismiss,
    this.width = 240,
    this.height = 490,
  });

  final Device? device;
  final String? latestClipboardText;
  final int batteryLevel;
  final bool isCharging;
  final String carrier;
  final String? nowPlayingTitle;
  final String? nowPlayingArtist;
  final String? notificationAppName;
  final String? notificationTitle;
  final String? notificationText;
  final String? notificationTime;
  final VoidCallback? onMirrorTap;
  final VoidCallback? onCopyTap;
  final VoidCallback? onNotificationTap;
  final VoidCallback? onNotificationDismiss;
  final double width;
  final double height;

  @override
  State<PhoneMockupWidget> createState() => _PhoneMockupWidgetState();
}

class _PhoneMockupWidgetState extends State<PhoneMockupWidget> {
  late Timer _clockTimer;
  DateTime _currentTime = DateTime.now();
  bool _isNotificationDismissed = false;

  IconData _getAppIcon(String? appName) {
    final name = (appName ?? '').toLowerCase();
    if (name.contains('message') || name.contains('chat') || name.contains('sms')) {
      return Icons.chat_bubble;
    }
    if (name.contains('mail') || name.contains('gmail')) {
      return Icons.mail;
    }
    if (name.contains('whatsapp') || name.contains('telegram') || name.contains('signal')) {
      return Icons.send;
    }
    if (name.contains('call') || name.contains('phone')) {
      return Icons.phone;
    }
    if (name.contains('calendar') || name.contains('event')) {
      return Icons.calendar_today;
    }
    return Icons.notifications_active;
  }

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


  List<Color> _getWallpaperColors(String? theme) {
    switch (theme) {
      case 'emerald':
        return const [Color(0xFF064E3B), Color(0xFF022C22), Color(0xFF0D1117), Color(0xFF065F46)];
      case 'sunset':
        return const [Color(0xFF3B1E14), Color(0xFF1F110B), Color(0xFF0D1117), Color(0xFF2E1710)];
      case 'aurora':
        return const [Color(0xFF4F46E5), Color(0xFFE11D48), Color(0xFFF59E0B), Color(0xFF1E1B4B)];
      case 'dark':
      default:
        return const [Color(0xFF0D1117), Color(0xFF161B22), Color(0xFF090C10), Color(0xFF1F2428)];
    }
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = widget.device != null && widget.device!.isPaired;
    final deviceName = widget.device?.name ?? 'Android Phone';
    final int effectiveBattery = widget.device?.batteryLevel ?? widget.batteryLevel;
    final bool effectiveCharging = widget.device?.isCharging ?? widget.isCharging;
    final String effectiveCarrier = widget.device?.carrier ?? widget.carrier;
    final String? effectiveTitle = widget.device?.nowPlayingTitle ?? widget.nowPlayingTitle;
    final String? effectiveArtist = widget.device?.nowPlayingArtist ?? widget.nowPlayingArtist;
    final wallpaperColors = _getWallpaperColors(widget.device?.wallpaperTheme);

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
            // Dynamic Wallpaper Theme Gradient
            AnimatedContainer(
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeInOut,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: wallpaperColors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            // Subtle Glass Overlay
            Container(
              color: Colors.black.withValues(alpha: 0.2),
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
                          Text(
                            effectiveCarrier,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.wifi, size: 13, color: Colors.white),
                          const SizedBox(width: 4),
                          Icon(
                            effectiveCharging ? Icons.battery_charging_full : Icons.battery_std,
                            size: 14,
                            color: Colors.greenAccent,
                          ),
                          Text(
                            ' $effectiveBattery%',
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

                // Live Android Lock Screen Notification Card
                if (widget.notificationTitle != null &&
                    widget.notificationTitle!.isNotEmpty &&
                    !_isNotificationDismissed)
                  Padding(
                    padding: const EdgeInsets.only(top: 14, left: 14, right: 14),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B).withValues(alpha: 0.88),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF3B82F6), Color(0xFF6366F1)],
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Icon(
                                  _getAppIcon(widget.notificationAppName),
                                  size: 11,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  widget.notificationAppName ?? 'Messages',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                widget.notificationTime ?? 'now',
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 10,
                                ),
                              ),
                              const SizedBox(width: 6),
                              InkWell(
                                onTap: () {
                                  setState(() {
                                    _isNotificationDismissed = true;
                                  });
                                  widget.onNotificationDismiss?.call();
                                },
                                child: const Icon(
                                  Icons.close,
                                  size: 14,
                                  color: Colors.white54,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.notificationTitle!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (widget.notificationText != null &&
                              widget.notificationText!.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              widget.notificationText!,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                height: 1.25,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF3B82F6).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(0xFF60A5FA).withValues(alpha: 0.3),
                                  ),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.reply,
                                      size: 11,
                                      color: Color(0xFF93C5FD),
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      'Reply',
                                      style: TextStyle(
                                        color: Color(0xFF93C5FD),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  'Mark as read',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                // Now Playing Media Widget Pill ONLY when media is active on phone
                if (isConnected && effectiveTitle != null && effectiveTitle.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12, left: 14, right: 14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [Color(0xFFEC4899), Color(0xFF8B5CF6)]),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.music_note, color: Colors.white, size: 18),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  effectiveTitle,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  effectiveArtist ?? 'Splurter Continuity',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 10,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.pause_circle_filled, color: Colors.white, size: 22),
                        ],
                      ),
                    ),
                  ),

                const Spacer(),

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
