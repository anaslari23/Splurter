const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { getFirestore } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');
const { initializeApp } = require('firebase-admin/app');

initializeApp();

/**
 * onDeviceLinked — fires whenever a device document is created or updated
 * under /users/{uid}/devices/{deviceId}.
 *
 * When a user has both an 'android' and 'macos' device registered, this
 * function ensures both devices are aware of each other's deviceId by
 * writing a /users/{uid}/pair summary document, and sends an FCM wakeup
 * to the Android device so it starts the relay loop even if the app is closed.
 */
exports.onDeviceLinked = onDocumentCreated(
  'users/{uid}/devices/{deviceId}',
  async (event) => {
    const { uid } = event.params;
    const db = getFirestore();

    // Load all devices for this user
    const devicesSnap = await db.collection(`users/${uid}/devices`).get();
    const devices = devicesSnap.docs.map((d) => ({ id: d.id, ...d.data() }));

    const android = devices.find((d) => d.platform === 'android');
    const mac = devices.find((d) => d.platform === 'macos');

    if (!android || !mac) return; // not paired yet — wait for second device

    // Write/update the pair summary
    await db.doc(`users/${uid}/pair`).set({
      androidDeviceId: android.id,
      macDeviceId: mac.id,
      linkedAt: new Date().toISOString(),
    }, { merge: true });

    console.log(`Linked pair for uid=${uid}: android=${android.id} mac=${mac.id}`);

    // Wake Android via FCM so it starts the relay loop from background
    const fcmToken = android.fcmToken;
    if (fcmToken) {
      try {
        await getMessaging().send({
          token: fcmToken,
          data: { action: 'startRelay', macDeviceId: mac.id },
          android: { priority: 'high' },
        });
        console.log(`FCM wakeup sent to Android device ${android.id}`);
      } catch (e) {
        console.error('FCM wakeup failed:', e);
      }
    }
  }
);

/**
 * getTurnCredentials — issues ephemeral TURN credentials server-side.
 * Configure TURN_CREDENTIALS_JSON as a Firebase secret before deploying.
 */
exports.getTurnCredentials = onCall({ secrets: ['TURN_CREDENTIALS_JSON'] }, (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  const credentials = JSON.parse(process.env.TURN_CREDENTIALS_JSON || '{}');
  if (!credentials.urls || !credentials.username || !credentials.credential) {
    throw new HttpsError('failed-precondition', 'TURN is not configured.');
  }
  return credentials;
});
