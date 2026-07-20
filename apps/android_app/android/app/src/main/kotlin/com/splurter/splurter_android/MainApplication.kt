package com.splurter.splurter_android

import android.app.Application

class MainApplication : Application() {
    lateinit var clipboardHandler: ClipboardChannelHandler
    lateinit var discoveryHandler: DiscoveryChannelHandler
    lateinit var networkHandler: NetworkChannelHandler
    lateinit var fileHandler: FileChannelHandler
}
