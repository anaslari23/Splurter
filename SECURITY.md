# Security

## Model

- The Mac and phone talk directly over your local network. There is no server and no account.
- Pairing needs physical access to the Mac screen: the QR code carries a single-use token. After pairing, reconnecting requires both devices' stored keys, and the Mac drops connections from unknown phones.
- All traffic (messages, files, video, audio) is encrypted with ChaCha20-Poly1305 under keys from four X25519 agreements. See [docs/PROTOCOL.md](docs/PROTOCOL.md).
- Sensitive actions need consent on the phone: screen mirroring needs a tap on the notification and Android's capture prompt each time, and remote input is ignored unless a mirroring session is live. Notification access, accessibility (screen control) and call/SMS permissions are granted by the user in Android settings.

## Known gaps

- A paired phone's static public key is sent in clear in the handshake (it identifies the device to someone watching your LAN, but does not let them connect).
- Keys are stored in plain files (`identity.key` with mode 0600 on the Mac, app-private preferences on Android), not in the Keychain or Android Keystore.
- The Mac app is ad-hoc signed and not notarized.
- This has had no external audit.

## Reporting

Please report vulnerabilities privately through GitHub's "Report a vulnerability" (Security tab) rather than a public issue.
