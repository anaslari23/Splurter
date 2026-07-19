package com.splurter.splurter_android

import android.app.Application

class MainApplication : Application() {
    lateinit var clipboardHandler: ClipboardChannelHandler
        private set
    lateinit var discoveryHandler: DiscoveryChannelHandler
        private set
    lateinit var networkHandler: NetworkChannelHandler
        private set
    lateinit var fileHandler: FileChannelHandler
        private set
}
