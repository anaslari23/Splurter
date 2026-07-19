package com.splurter.splurter_android

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val app = application as MainApplication
        app.clipboardHandler = ClipboardChannelHandler(this, flutterEngine)
        app.discoveryHandler = DiscoveryChannelHandler(this, flutterEngine)
        app.networkHandler = NetworkChannelHandler(this, flutterEngine)
        app.fileHandler = FileChannelHandler(this, flutterEngine)

        app.clipboardHandler.install()
        app.discoveryHandler.install()
        app.networkHandler.install()
        app.fileHandler.install()
    }

    override fun onDestroy() {
        super.onDestroy()
        val app = application as? MainApplication ?: return
        app.clipboardHandler.dispose()
        app.discoveryHandler.dispose()
        app.networkHandler.dispose()
        app.fileHandler.dispose()
    }
}
