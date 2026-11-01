# Splurter protocol (version 2)

One TCP connection per phone, carrying encrypted, length-prefixed frames. The Mac listens; the phone connects. Reference implementations: `native/mac/Sources/Splurter/{Crypto,Link}.swift` and `native/android/app/src/main/kotlin/app/splurter/Link.kt`.

## Discovery and pairing

- The Mac advertises Bonjour service `_splurter._tcp` with TXT record `id` = the first 8 bytes of SHA-256(Mac static public key), hex. The phone uses it to find *its* Mac, and falls back to the last address from the QR.
- **QR payload** (JSON): `{"v":2, "host":"<LAN IPv4>", "port":<n>, "key":"<base64 Mac static X25519 public key>", "tok":"<base64 16 random bytes>"}`. The token is single-use: it is replaced after one successful pairing.
- Each side has a long-lived X25519 static key (Mac: `~/Library/Application Support/Splurter/identity.key`, mode 0600; phone: app-private preferences). The Mac stores the public keys of paired phones in `devices.json`.

## Handshake

| Direction | Bytes |
|---|---|
| phone → Mac | `ephPub (32)` `mode (1)` `staticPub (32)` |
| Mac → phone | `ephPub (32)` |

`mode` is `0` to pair (the phone proved knowledge of the QR token) or `1` to reconnect. For `mode 1` the Mac drops the connection unless `staticPub` is in its paired list.

Keys come from four X25519 agreements (`s` = static, `e` = ephemeral, `m` = Mac, `p` = phone):

```
ikm  = DH(s_m, e_p) ‖ DH(e_m, e_p) ‖ DH(s_m, s_p) ‖ DH(e_m, s_p)
okm  = HKDF-SHA256(ikm, salt = token if mode 0 else empty, info = "splurter/v2", L = 64)
phone → Mac key = okm[0..32]      Mac → phone key = okm[32..64]
```

Possession of the right keys is proven by the first frame decrypting. On a first pairing the Mac adds the phone's static key to its paired list only after that first frame (a `hello`) authenticates, and then rotates the token.

## Frames

```
[ length : 4 bytes, big endian ][ ciphertext ‖ 16-byte Poly1305 tag ]      length = size of the second part, 16 … 1 MiB
```

AEAD is ChaCha20-Poly1305 with a 12-byte nonce = 4 zero bytes + an 8-byte big-endian per-direction frame counter (starting at 0). No associated data. A frame that fails to authenticate closes the connection.

The first byte of the decrypted plaintext is the **frame type**:

| Type | Meaning | Layout after the type byte |
|---|---|---|
| `0` | JSON message | UTF-8 JSON object with a `"t"` field |
| `1` | File chunk | `id (4, big endian)` `data` (up to 192 KiB) |
| `2` | Video | `kind (1: 0 SPS/PPS, 1 keyframe, 2 delta)` `H.264 Annex-B bytes` |
| `3` | Reserved | Unused. Call audio does not use the Splurter link (see `native/callbridge`). |

The Mac sends a `ping` every 10 s; the phone treats 35 s of silence as a dead link and reconnects with backoff (1 s doubling to 30 s).

## JSON messages (`"t"`)

`→M` = phone to Mac, `→P` = Mac to phone.

| `t` | Dir | Fields | Notes |
|---|---|---|---|
| `hello` | both | `name` | First message each way; confirms the session. |
| `ping` | →P | | Keepalive. |
| `clip` | both | `text` | Set the clipboard. |
| `notif` | →M | `id`, `pkg`, `app`, `title`, `text`, `canReply`, `sync` | `sync:true` = quiet catch-up after reconnect. |
| `notif_gone` | →M | `id` | Notification removed on the phone. |
| `media` | →M | `sessions[]`: `pkg`, `title`, `artist`, `app`, `playing`, `dur`, `pos` (ms), `speed`, `art` (base64 JPEG, once per track) | All active media sessions, playing first. |
| `volume` | →M | `level`, `max` | Phone music volume. |
| `media_cmd` | M→ | `pkg`, `cmd` (`play` `pause` `next` `prev` `seek`), `pos` (ms) | Transport control for one player. |
| `volume_set` | M→ | `level` (0–1) | Set the phone's music volume. |
| `app_icon` | →M | `pkg`, `png` (base64) | Sent once per package per connection, before its first `notif`. |
| `dismiss` | →P | `id` | Dismiss on the phone. |
| `reply` | →P | `id`, `text` | Inline reply via the notification's remote input. |
| `call` | →M | `state` (`ringing`/`offhook`/`idle`), `number`, `name` | |
| `call_answer`, `call_end` | →P | | Answer, or decline/hang up. |
| `dial` | →P | `number` | |
| `sms_send` | →P | `to`, `text` | |
| `sms_sent` | →M | `to` | |
| `file`, `file_end` | both | `id`, `name`, `size` (`file` only) | Bracket the type-1 chunks for `id`. Receivers strip any path from `name`. |
| `mirror_start`, `mirror_stop` | →P | | Start needs the user's tap and consent on the phone. |
| `mirror_info` | →M | `w`, `h` | Encoded video size. |
| `mirror_state` | →M | `state` (`waiting`, `live`, `denied`, `stopped`) | |
| `tap` | →P | `x`, `y` (0…1), `ms` | Long press if `ms` is large. |
| `swipe` | →P | `x1`, `y1`, `x2`, `y2` (0…1), `ms` | Also used for scrolling. |
| `key` | →P | `k` (`back`, `home`, `recents`, `enter`, `del`) | |
| `text` | →P | `s` | Appended to the focused field. |

`tap`, `swipe`, `key` and `text` are ignored by the phone unless a mirroring session is live.

## Compatibility

Unknown `t` values are ignored. There is no version negotiation yet: the version lives in the QR payload (`v`) and the HKDF `info` string, so an incompatible change bumps both.
