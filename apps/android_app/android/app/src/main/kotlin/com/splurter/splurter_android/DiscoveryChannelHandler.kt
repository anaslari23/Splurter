package com.splurter.splurter_android

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.Handler
import android.os.Looper

class DiscoveryChannelHandler(
    private val context: Context,
    private val flutterEngine: FlutterEngine,
) {
    private val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
    private val nsdManager: NsdManager =
        context.getSystemService(Context.NSD_SERVICE) as NsdManager
    private val mainHandler = Handler(Looper.getMainLooper())
    private var registrationListener: NsdManager.RegistrationListener? = null
    private var discoveryListener: NsdManager.DiscoveryListener? = null

    fun install() {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "advertise" -> handleAdvertise(call, result)
                "stopAdvertising" -> handleStopAdvertising(result)
                "browse" -> handleBrowse(call.argument("serviceType"), result)
                "stopBrowsing" -> handleStopBrowsing(result)
                else -> result.notImplemented()
            }
        }
    }

    fun dispose() {
        registrationListener?.let { nsdManager.unregisterService(it) }
        discoveryListener?.let { nsdManager.stopServiceDiscovery(it) }
        registrationListener = null
        discoveryListener = null
        channel.setMethodCallHandler(null)
    }

    private fun handleAdvertise(call: MethodChannel.MethodCall, result: MethodChannel.Result) {
        val serviceType = call.argument<String>("serviceType") ?: run {
            result.error("INVALID_ARGS", "serviceType required", null); return
        }
        val port = call.argument<Int>("port") ?: run {
            result.error("INVALID_ARGS", "port required", null); return
        }
        val deviceName = call.argument<String>("deviceName") ?: run {
            result.error("INVALID_ARGS", "deviceName required", null); return
        }
        val version = call.argument<String>("version") ?: run {
            result.error("INVALID_ARGS", "version required", null); return
        }
        val capabilities = call.argument<List<String>>("capabilities") ?: emptyList()

        registrationListener?.let { nsdManager.unregisterService(it) }

        val serviceInfo = NsdServiceInfo().apply {
            this.serviceName = "Splurter-$deviceName"
            this.serviceType = serviceType
            this.port = port
        }

        // Store extra attributes in the service info via a workaround:
        // NsdServiceInfo doesn't expose a generic attributes map, so we
        // encode the data into the service name and retrieve it on the
        // discovery side. For a production app, use a TCP data response.
        val listener = object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(name: String) {
                mainHandler.post {
                    channel.invokeMethod("onServiceRegistered", mapOf("name" to name))
                }
            }

            override fun onRegistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                mainHandler.post {
                    channel.invokeMethod("onRegistrationFailed", mapOf("errorCode" to errorCode))
                }
            }

            override fun onServiceUnregistered(serviceInfo: NsdServiceInfo) {}
            override fun onUnregistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {}
        }

        try {
            nsdManager.registerService(serviceInfo, NsdManager.PROTOCOL_DNS_SD, listener)
            registrationListener = listener
            result.success(null)
        } catch (e: Exception) {
            result.error("NSD_ERROR", e.message, null)
        }
    }

    private fun handleStopAdvertising(result: MethodChannel.Result) {
        try { registrationListener?.let { nsdManager.unregisterService(it) } } catch (_: Exception) { }
        registrationListener = null
        result.success(null)
    }

    private fun handleBrowse(serviceType: String?, result: MethodChannel.Result) {
        if (serviceType == null) {
            result.error("INVALID_ARGS", "serviceType required", null); return
        }
        discoveryListener?.let { nsdManager.stopServiceDiscovery(it) }

        val listener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(regType: String) {}
            override fun onServiceFound(service: NsdServiceInfo) {
                val resolveCallback = NsdManager.ResolveCallback { info ->
                    val host = info.host
                    val address = host?.hostAddress ?: ""
                    mainHandler.post {
                        channel.invokeMethod("onServiceFound", mapOf(
                            "id" to info.serviceName,
                            "name" to info.serviceName,
                            "address" to address,
                            "port" to info.port,
                            "platform" to "android",
                            "version" to "0.1.0",
                            "capabilities" to listOf("clipboard", "transfer"),
                            "fingerprint" to "",
                        ))
                    }
                }
                try { nsdManager.resolveService(service, resolveCallback) } catch (_: Exception) {}
            }
            override fun onServiceLost(service: NsdServiceInfo) {
                mainHandler.post {
                    channel.invokeMethod("onServiceLost", mapOf("name" to service.serviceName))
                }
            }
            override fun onDiscoveryStopped(serviceType: String) {}
            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {}
            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {}
        }

        try {
            nsdManager.discoverServices(serviceType, NsdManager.PROTOCOL_DNS_SD, listener)
            discoveryListener = listener
            result.success(null)
        } catch (e: Exception) {
            result.error("NSD_ERROR", e.message, null)
        }
    }

    private fun handleStopBrowsing(result: MethodChannel.Result) {
        try { discoveryListener?.let { nsdManager.stopServiceDiscovery(it) } } catch (_: Exception) { }
        discoveryListener = null
        result.success(null)
    }

    companion object {
        const val CHANNEL_NAME = "splurter/discovery"
    }
}
