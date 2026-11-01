import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:continuity_core/continuity_core.dart';

/// Holds the currently active incoming or in-progress phone call event.
/// Set to null when the call ends, is missed, or is declined.
final activeCallProvider = StateProvider<PhoneCallEvent?>((ref) => null);
