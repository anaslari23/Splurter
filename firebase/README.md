# Firebase setup

Create one Firebase project, enable Email Link sign-in, Firestore, Storage,
Cloud Functions, and Cloud Messaging. Register Android (`com.splurter.splurter`)
and macOS apps, then generate FlutterFire configuration locally; do not commit
project credentials or generated configuration files.

Deploy `firestore.rules` and `storage.rules` before enabling any client. Set the
`TURN_CREDENTIALS_JSON` Firebase secret to the short-lived TURN credential
payload issued by the selected provider, then deploy `functions`.

The client implementation must reject relay data unless it is from its paired
device and decrypt it locally with the pairing session key.
