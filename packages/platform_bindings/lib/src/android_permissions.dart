import 'package:flutter/services.dart';

const _permChannel = MethodChannel('splurter/permissions');

class AndroidPermissionStatus {
  const AndroidPermissionStatus({
    required this.notificationAccess,
    required this.imeEnabled,
    required this.imeSelected,
    required this.batteryExempt,
  });

  final bool notificationAccess;
  final bool imeEnabled;
  final bool imeSelected;
  final bool batteryExempt;

  bool get allGranted => notificationAccess && batteryExempt && (imeEnabled || imeSelected);
}

Future<AndroidPermissionStatus> getAndroidPermissionStatus() async {
  try {
    final Map? res = await _permChannel.invokeMethod('checkStatus');
    if (res == null) {
      return const AndroidPermissionStatus(
        notificationAccess: false,
        imeEnabled: false,
        imeSelected: false,
        batteryExempt: false,
      );
    }
    return AndroidPermissionStatus(
      notificationAccess: res['notificationAccess'] as bool? ?? false,
      imeEnabled: res['imeEnabled'] as bool? ?? false,
      imeSelected: res['imeSelected'] as bool? ?? false,
      batteryExempt: res['batteryExempt'] as bool? ?? false,
    );
  } catch (_) {
    return const AndroidPermissionStatus(
      notificationAccess: false,
      imeEnabled: false,
      imeSelected: false,
      batteryExempt: false,
    );
  }
}

Future<void> openNotificationListenerSettings() async {
  try {
    await _permChannel.invokeMethod('openNotificationListenerSettings');
  } catch (_) {}
}

Future<void> openInputMethodSettings() async {
  try {
    await _permChannel.invokeMethod('openInputMethodSettings');
  } catch (_) {}
}

Future<void> showInputMethodPicker() async {
  try {
    await _permChannel.invokeMethod('showInputMethodPicker');
  } catch (_) {}
}

Future<void> requestBatteryExemption() async {
  try {
    await _permChannel.invokeMethod('requestBatteryExemption');
  } catch (_) {}
}
