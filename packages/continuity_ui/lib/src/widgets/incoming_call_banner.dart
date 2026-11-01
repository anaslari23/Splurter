import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:continuity_core/continuity_core.dart';

/// Apple CallKit / FaceTime style floating Call HUD for macOS
class IncomingCallBanner extends StatefulWidget {
  const IncomingCallBanner({
    super.key,
    required this.call,
    required this.onAnswer,
    required this.onDecline,
  });

  final PhoneCallEvent call;
  final VoidCallback onAnswer;
  final VoidCallback onDecline;

  @override
  State<IncomingCallBanner> createState() => _IncomingCallBannerState();
}

class _IncomingCallBannerState extends State<IncomingCallBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;
  Timer? _durationTimer;
  int _secondsElapsed = 0;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    if (widget.call.state == 'offhook') {
      _startTimer();
    }
  }

  @override
  void didUpdateWidget(covariant IncomingCallBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.call.state == 'offhook' && oldWidget.call.state != 'offhook') {
      _startTimer();
    }
  }

  void _startTimer() {
    _durationTimer?.cancel();
    _secondsElapsed = 0;
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _secondsElapsed++);
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _durationTimer?.cancel();
    super.dispose();
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final isRinging = widget.call.state == 'ringing';
    final isOffhook = widget.call.state == 'offhook';
    final displayName = widget.call.callerName?.isNotEmpty == true
        ? widget.call.callerName!
        : (widget.call.number.isNotEmpty ? widget.call.number : 'Incoming Call');

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          width: 360,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF1E293B).withValues(alpha: 0.88),
                const Color(0xFF0F172A).withValues(alpha: 0.94),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 32,
                offset: const Offset(0, 14),
              ),
              if (isRinging)
                BoxShadow(
                  color: const Color(0xFF22C55E).withValues(alpha: 0.25),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  // Animated Contact Avatar
                  ScaleTransition(
                    scale: isRinging ? _pulseAnimation : const AlwaysStoppedAnimation(1.0),
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            isOffhook
                                ? const Color(0xFF3B82F6)
                                : const Color(0xFF22C55E),
                            const Color(0xFF065F46),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (isOffhook
                                    ? const Color(0xFF3B82F6)
                                    : const Color(0xFF22C55E))
                                .withValues(alpha: 0.4),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  // Caller Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.phone_iphone_rounded,
                              size: 13,
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isOffhook
                                  ? 'Call in Progress • ${_formatDuration(_secondsElapsed)}'
                                  : 'Android Cellular Call',
                              style: TextStyle(
                                color: isOffhook
                                    ? const Color(0xFF60A5FA)
                                    : const Color(0xFF34D399),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                          ),
                        ),
                        if (widget.call.number.isNotEmpty &&
                            widget.call.callerName != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            widget.call.number,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Decline / Hangup Button
                  _CallActionButton(
                    icon: Icons.call_end_rounded,
                    label: isOffhook ? 'End' : 'Decline',
                    color: const Color(0xFFEF4444),
                    onTap: widget.onDecline,
                  ),
                  if (isRinging) ...[
                    // Accept Button
                    _CallActionButton(
                      icon: Icons.call_rounded,
                      label: 'Accept',
                      color: const Color(0xFF22C55E),
                      onTap: widget.onAnswer,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CallActionButton extends StatelessWidget {
  const _CallActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
