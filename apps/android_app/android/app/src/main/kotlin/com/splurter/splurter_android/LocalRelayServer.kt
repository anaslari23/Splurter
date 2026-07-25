package com.splurter.splurter_android

import android.util.Log
import kotlinx.coroutines.*
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.ServerSocket
import java.net.Socket

/**
 * LocalRelayServer — a minimal TCP server listening on port 53317.
 *
 * When the Mac discovers Android via BLE and connects directly over LAN,
 * it sends RelayEnvelope JSON payloads over this socket instead of Firestore.
 * This gives sub-100ms clipboard and notification delivery on local Wi-Fi.
 *
 * Protocol: each message is a newline-terminated JSON string matching
 * the RelayEnvelope schema (same as Firestore signals).
 */
class LocalRelayServer(
    private val onEnvelopeReceived: (Map<String, String>) -> Unit
) {
    companion object {
        const val PORT = 53317
        private const val TAG = "LocalRelayServer"
    }

    private var serverSocket: ServerSocket? = null
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    fun start() {
        scope.launch {
            try {
                serverSocket = ServerSocket(PORT)
                Log.d(TAG, "Local relay server listening on port $PORT")
                while (isActive) {
                    val client: Socket = serverSocket?.accept() ?: break
                    launch { handleClient(client) }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Server error: ${e.message}")
            }
        }
    }

    private suspend fun handleClient(socket: Socket) {
        withContext(Dispatchers.IO) {
            try {
                socket.use {
                    val reader = BufferedReader(InputStreamReader(it.getInputStream()))
                    var line: String?
                    while (reader.readLine().also { line = it } != null) {
                        val raw = line ?: continue
                        // Parse minimal JSON envelope — avoid heavy deps in native layer
                        val map = parseSimpleJson(raw)
                        if (map.isNotEmpty()) {
                            withContext(Dispatchers.Main) {
                                onEnvelopeReceived(map)
                            }
                        }
                    }
                }
            } catch (e: Exception) {
                Log.d(TAG, "Client disconnected: ${e.message}")
            }
        }
    }

    /** Minimal JSON string parser — avoids adding gson/moshi to native code. */
    private fun parseSimpleJson(json: String): Map<String, String> {
        return try {
            json.trim('{', '}').split(",")
                .mapNotNull { pair ->
                    val parts = pair.split(":", limit = 2)
                    if (parts.size == 2) {
                        val key = parts[0].trim().trim('"')
                        val value = parts[1].trim().trim('"')
                        key to value
                    } else null
                }.toMap()
        } catch (e: Exception) { emptyMap() }
    }

    fun stop() {
        scope.cancel()
        try { serverSocket?.close() } catch (_: Exception) {}
        serverSocket = null
    }
}
