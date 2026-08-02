import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_types/shared_types.dart';


// Current auth user stream
final authUserProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

// Sign-in notifier
final authNotifierProvider = AsyncNotifierProvider<AuthNotifier, User?>(() => AuthNotifier());

class AuthNotifier extends AsyncNotifier<User?> {
  final _auth = FirebaseAuth.instance;
  final _googleSignIn = GoogleSignIn(scopes: ['email', 'profile']);

  @override
  Future<User?> build() async {
    return _auth.currentUser;
  }

  Future<void> signInWithGoogle() async {
    state = const AsyncLoading();
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        state = const AsyncData(null);
        return;
      }
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final userCredential = await _auth.signInWithCredential(credential);
      state = AsyncData(userCredential.user);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> signInAnonymously() async {
    state = const AsyncLoading();
    try {
      final userCredential = await _auth.signInAnonymously();
      state = AsyncData(userCredential.user);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
    state = const AsyncData(null);
  }
}

// Register device in Firestore under users/{uid}/devices/{deviceId}
Future<void> registerDevice({
  required String uid,
  required String deviceId,
  required String platform,
  required String name,
  String? ipAddress,
  int? port,
  String? fcmToken,
  int? batteryLevel,
  bool? isCharging,
  String? carrier,
  String? wallpaperTheme,
}) async {
  await FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('devices')
      .doc(deviceId)
      .set({
    'deviceId': deviceId,
    'platform': platform,
    'name': name,
    'ipAddress': ipAddress,
    'port': port ?? 53317,
    'fcmToken': fcmToken,
    if (batteryLevel != null) 'batteryLevel': batteryLevel,
    if (isCharging != null) 'isCharging': isCharging,
    if (carrier != null) 'carrier': carrier,
    if (wallpaperTheme != null) 'wallpaperTheme': wallpaperTheme,
    'registeredAt': FieldValue.serverTimestamp(),
    'lastSeen': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

/// Real-time stream of devices registered under users/{uid}/devices
final remoteDevicesStreamProvider = StreamProvider.family<List<Device>, String>((ref, uid) {
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('devices')
      .snapshots()
      .map((snapshot) {
    return snapshot.docs.map((doc) {
      final data = doc.data();
      return Device(
        id: data['deviceId'] ?? doc.id,
        name: data['name'] ?? 'Device',
        platform: data['platform'] ?? 'unknown',
        address: data['ipAddress'] ?? 'relay',
        port: data['port'] ?? 53317,
        version: '1.0',
        capabilities: const ['clipboard', 'notifications', 'fileTransfer'],
        isPaired: true,
        batteryLevel: data['batteryLevel'] as int? ?? 88,
        isCharging: data['isCharging'] as bool? ?? false,
        carrier: data['carrier'] as String? ?? '5G',
        nowPlayingTitle: data['nowPlayingTitle'] as String?,
        nowPlayingArtist: data['nowPlayingArtist'] as String?,
        wallpaperTheme: data['wallpaperTheme'] as String?,
      );
    }).toList();
  });
});

