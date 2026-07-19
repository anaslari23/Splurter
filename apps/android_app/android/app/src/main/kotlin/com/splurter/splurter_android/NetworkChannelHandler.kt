package com.splurter.splurter_android

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.wifi.WifiManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class NetworkChannelHandler(
    private val context: Context,
    private val flutterEngine: FlutterEngine,
) {
    private val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
    private val connectivityManager: ConnectivityManager =
        context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    fun install() {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getNetworkInfo" -> getNetworkInfo(result)
                "startListening" -> startListening(result)
                else -> result.notImplemented()
            }
        }
    }

    fun dispose() {
        networkCallback?.let { connectivityManager.unregisterNetworkCallback(it) }
        networkCallback = null
        channel.setMethodCallHandler(null)
    }

    private fun getNetworkInfo(result: MethodChannel.Result) {
        val activeNetwork = connectivityManager.activeNetwork
        val caps = activeNetwork?.let { connectivityManager.getNetworkCapabilities(it) }
        val isConnected = caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true
        val isWifi = caps?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
        val ip = if (isWifi) wifiIpAddress() else ""
        result.success(mapOf("ipAddress" to ip, "isWifi" to isWifi, "isConnected" to isConnected))
    }

    private fun startListening(result: MethodChannel.Result) {
        networkCallback?.let { connectivityManager.unregisterNetworkCallback(it) }

        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                val caps = connectivityManager.getNetworkCapabilities(network)
                val isWifi = caps?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
                val ip = if (isWifi) wifiIpAddress() else ""
                channel.invokeMethod(
                    "onConnectivityChanged",
                    mapOf("isConnected" to true, "ipAddress" to ip, "isWifi" to isWifi),
                )
            }

            override fun onLost(network: Network) {
                channel.invokeMethod(
                    "onConnectivityChanged",
                    mapOf("isConnected" to false, "ipAddress" to "", "isWifi" to false),
                )
            }
        }

        connectivityManager.registerDefaultNetworkCallback(callback)
        networkCallback = callback
        result.success(null)
    }

    private fun wifiIpAddress(): String {
        @Suppress("DEPRECATION")
        val wifiManager = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        @Suppress("DEPRECATION")
        val dhcp = wifiManager.dhcpInfo
        return "${dhcp.ipAddress and 0xFF}.${dhcp.ipAddress shr 8 and 0xFF}.${dhcp.ipAddress shr 16 and 0xFF}.${dhcp.ipAddress shr 24 and 0xFF}"
    }

    companion object {
        const val CHANNEL_NAME = "splurter/network"
    }
}
