package com.splurter.splurter_android

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.content.Context
import android.os.ParcelUuid
import java.net.NetworkInterface
import java.util.UUID

/**
 * BleAdvertiser — Advertises the device's local Wi-Fi IP in a BLE
 * peripheral manufacturer data payload (26 bytes max).
 *
 * The Mac's CoreBluetooth scanner reads this payload, extracts the IP,
 * and opens a direct NWConnection TCP socket for sub-100ms LAN relay.
 * This avoids the Firebase cloud relay entirely when on the same Wi-Fi.
 *
 * Architecture mirrors Google Nearby Share: BLE for discovery, Wi-Fi for data.
 */
class BleAdvertiser(private val context: Context) {

    companion object {
        // Unique service UUID that identifies Splurter devices
        val SERVICE_UUID: UUID = UUID.fromString("A1B2C3D4-E5F6-7890-ABCD-EF1234567890")
        const val LOCAL_RELAY_PORT = 53317
    }

    private var advertiser: BluetoothLeAdvertiser? = null
    private val callback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
            android.util.Log.d("BleAdvertiser", "BLE advertising started")
        }
        override fun onStartFailure(errorCode: Int) {
            android.util.Log.e("BleAdvertiser", "BLE advertising failed: $errorCode")
        }
    }

    fun start() {
        val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager ?: return
        val adapter = bluetoothManager.adapter ?: return
        if (!adapter.isEnabled) return

        advertiser = adapter.bluetoothLeAdvertiser ?: return

        val ip = getWifiIpAddress() ?: return
        // Encode IP as 4 bytes + port as 2 bytes = 6 bytes manufacturer data
        val ipBytes = ip.split(".").map { it.toInt().toByte() }.toByteArray()
        val portBytes = byteArrayOf(
            (LOCAL_RELAY_PORT shr 8).toByte(),
            (LOCAL_RELAY_PORT and 0xFF).toByte()
        )
        val manufacturerData = ipBytes + portBytes

        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setConnectable(false)
            .setTimeout(0) // advertise indefinitely
            .build()

        val data = AdvertiseData.Builder()
            .addServiceUuid(ParcelUuid(SERVICE_UUID))
            .addManufacturerData(0x05CE /* Splurter company ID */, manufacturerData)
            .setIncludeDeviceName(false)
            .build()

        try {
            advertiser?.startAdvertising(settings, data, callback)
        } catch (e: SecurityException) {
            android.util.Log.e("BleAdvertiser", "BLE permission denied: ${e.message}")
        }
    }

    fun stop() {
        try {
            advertiser?.stopAdvertising(callback)
        } catch (e: SecurityException) { }
        advertiser = null
    }

    private fun getWifiIpAddress(): String? {
        return try {
            NetworkInterface.getNetworkInterfaces()?.toList()
                ?.filter { it.isUp && !it.isLoopback && it.name.startsWith("wlan") }
                ?.flatMap { it.inetAddresses.toList() }
                ?.firstOrNull { !it.isLoopbackAddress && it is java.net.Inet4Address }
                ?.hostAddress
        } catch (e: Exception) { null }
    }
}
