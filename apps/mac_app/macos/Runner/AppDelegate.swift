import Cocoa
import FlutterMacOS
import Network
import Foundation
import ServiceManagement
import UserNotifications

@main

class AppDelegate: FlutterAppDelegate {
    private var clipboardMonitor: ClipboardMonitor?
    private var browser: NWBrowser?
    private var advertiser: NWListener?
    private var fileHandler: FileHandler?
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    override func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as menu-bar accessory — no Dock icon, survives window close
        NSApp.setActivationPolicy(.accessory)

        setupPlatformChannels()
        requestNotificationPermission()
        registerLaunchAtLogin()
        startAdvertiser()
        startBrowser()
        setupStatusItem()
    }




    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if granted {
                print("[Splurter] macOS notification permission granted")
            }
        }
    }

    private func registerLaunchAtLogin() {
        guard #available(macOS 13.0, *) else { return }
        do {
            try SMAppService.mainApp.register()
        } catch {
            // The user can still start Splurter normally; this is commonly
            // unavailable in unsigned development builds.
            print("Launch at login unavailable: \(error)")
        }
    }

    override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func setupPlatformChannels() {
        // Try multiple ways to get the Flutter binary messenger
        let binaryMessenger: FlutterBinaryMessenger? = {
            if let vc = mainFlutterWindow?.contentViewController as? FlutterViewController {
                return vc.engine.binaryMessenger
            }
            if let vc = NSApplication.shared.windows.first?.contentViewController as? FlutterViewController {
                return vc.engine.binaryMessenger
            }
            return nil
        }()

        guard let messenger = binaryMessenger else { return }

        let clipboardChannel = FlutterMethodChannel(name: "splurter/clipboard", binaryMessenger: messenger)
        clipboardMonitor = ClipboardMonitor(channel: clipboardChannel)
        clipboardChannel.setMethodCallHandler { [weak self] call, result in
            self?.clipboardMonitor?.handle(call, result: result)
        }
        // Auto-start clipboard monitoring — runs in background even when window is hidden
        clipboardMonitor?.start()


        let discoveryChannel = FlutterMethodChannel(name: "splurter/discovery", binaryMessenger: messenger)
        let discoveryHandler = DiscoveryHandler(channel: discoveryChannel, advertiser: advertiser)
        discoveryChannel.setMethodCallHandler(discoveryHandler.handle)

        let fileChannel = FlutterMethodChannel(name: "splurter/file", binaryMessenger: messenger)
        fileHandler = FileHandler(channel: fileChannel)
        fileChannel.setMethodCallHandler { [weak self] call, result in
            self?.fileHandler?.handle(call, result: result)
        }

        let networkChannel = FlutterMethodChannel(name: "splurter/network", binaryMessenger: messenger)
        networkChannel.setMethodCallHandler { [weak self] call, result in
            self?.handleNetworkCall(call: call, result: result)
        }

        // Register native macOS notification channel (show + dismiss + bounce-back to Android)
        setupNotificationChannel(messenger: messenger)
    }


    // MARK: - Menu Bar Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "antenna.radiowaves.left.and.right", accessibilityDescription: "Splurter")
            button.action = #selector(handleStatusClick)
            button.target = self
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Splurter — Connected", action: nil, keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "📋  Push Clipboard Now", action: #selector(pushClipboardNow), keyEquivalent: "v")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Show Window", action: #selector(showMainWindow), keyEquivalent: "")
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc private func pushClipboardNow() {
        // Trigger an immediate clipboard sync by invoking the Dart method
        guard let messenger = getBinaryMessenger() else { return }
        let ch = FlutterMethodChannel(name: "splurter/clipboard", binaryMessenger: messenger)
        ch.invokeMethod("pushNow", arguments: nil)
    }

    @objc private func handleStatusClick() {
        mainFlutterWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showMainWindow() {
        mainFlutterWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Discovery

    private func startAdvertiser() {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        advertiser = try? NWListener(using: parameters, on: 53317)
        advertiser?.newConnectionHandler = { [weak self] connection in
            print("Incoming connection from \(connection.endpoint)")
            connection.start(queue: .main)
            self?.handleIncomingConnection(connection)
        }
        advertiser?.start(queue: .main)

        // Publish via Bonjour so devices can find us
        guard let deviceName = Host.current().localizedName else { return }
        let service = NetService(
            domain: "local.",
            type: "_splurter._tcp.",
            name: "Splurter-\(deviceName)",
            port: 53317
        )
        service.publish(options: [.noAutoRename])
    }

    private func startBrowser() {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        browser = NWBrowser(for: .bonjour(type: "_splurter._tcp.", domain: nil), using: parameters)
        browser?.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                print("Browse failed: \(error)")
            }
        }
        browser?.start(queue: .main)
    }

    private func handleBrowseResult(_ result: NWBrowser.Result) {
        // NWBrowser.Result.endpoint is NWEndpoint; we only care about .service cases.
        // Pattern matching with associated values is causing a Swift compiler diagnostic
        // issue, so we extract fields defensively.
        let endpoint = result.endpoint
        var serviceName: String? = nil
        var hostname: String? = nil
        var port: NWEndpoint.Port? = nil

        switch endpoint {
        case .service(let name, let type, let domain, let interface):
            serviceName = name
            _ = type
            _ = domain
            _ = interface
            // The endpoint doesn't expose port/hostname directly here; rely on
            // the browse results metadata, but skip — we'll use a placeholder
            // for now since NWBrowser.Result.service doesn't include the
            // resolved host/port in this codepath.
            hostname = "unknown"
            port = NWEndpoint.Port(integerLiteral: 53317)
        default:
            return
        }

        guard let sName = serviceName, let host = hostname, let p = port else { return }

        var ip = host
        _ = ip  // Will be replaced when resolved properly via NWConnection.

        let messenger: FlutterBinaryMessenger? = {
            if let vc = mainFlutterWindow?.contentViewController as? FlutterViewController {
                return vc.engine.binaryMessenger
            }
            if let vc = NSApplication.shared.windows.first?.contentViewController as? FlutterViewController {
                return vc.engine.binaryMessenger
            }
            return nil
        }()

        guard let messenger = messenger else { return }

        let channel = FlutterMethodChannel(
            name: "splurter/discovery",
            binaryMessenger: messenger
        )
        channel.invokeMethod("onServiceFound", arguments: [
            "id": sName,
            "name": sName,
            "address": ip,
            "port": p.rawValue,
            "platform": "macos",
            "version": "0.1.0",
            "capabilities": ["clipboard", "transfer"],
            "fingerprint": "",
        ])
    }

    private func handleIncomingConnection(_ connection: NWConnection) {
        // Placeholder: receive messages from the remote device.
        // A full implementation parses ContinuityMessage and dispatches to Dart.
        print("Connection state: \(connection.state)")
    }

    // MARK: - Network

    private func handleNetworkCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getNetworkInfo":
            let info = getNetworkInfoSync()
            result(info)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func getNetworkInfoSync() -> [String: Any] {
        var ipAddress = ""
        var isWifi = false
        var isConnected = false

        let semaphore = DispatchSemaphore(value: 0)
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            isConnected = path.status == .satisfied
            isWifi = path.usesInterfaceType(.wifi)
            ipAddress = self?.getWiFiIPAddress() ?? ""
            monitor.cancel()
            semaphore.signal()
        }
        monitor.start(queue: .main)

        _ = semaphore.wait(timeout: .now() + 3)

        return [
            "ipAddress": ipAddress,
            "isWifi": isWifi,
            "isConnected": isConnected,
        ]
    }

    private func getWiFiIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr = firstAddr
        while true {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family

            if addrFamily == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(
                    interface.ifa_addr,
                    socklen_t(interface.ifa_addr.pointee.sa_len),
                    &hostname,
                    socklen_t(hostname.count),
                    nil,
                    socklen_t(0),
                    NI_NUMERICHOST
                )
                let name = String(cString: hostname)
                if !name.isEmpty && name != "127.0.0.1" {
                    address = name
                    break
                }
            }

            guard let next = interface.ifa_next else { break }
            ptr = next
        }
        return address
    }

    override func applicationWillTerminate(_ notification: Notification) {
        clipboardMonitor?.stop()
        browser?.cancel()
        advertiser?.cancel()
    }

    // MARK: - Helpers

    func getBinaryMessenger() -> FlutterBinaryMessenger? {
        if let vc = mainFlutterWindow?.contentViewController as? FlutterViewController {
            return vc.engine.binaryMessenger
        }
        if let vc = NSApplication.shared.windows.first?.contentViewController as? FlutterViewController {
            return vc.engine.binaryMessenger
        }
        return nil
    }

    /// Set up a Flutter ↔ Swift channel so Dart can request a native macOS
    /// notification (with a Dismiss action that bounces back to Android).
    private func setupNotificationChannel(messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: "splurter/native_notifications", binaryMessenger: messenger)
        channel.setMethodCallHandler { call, result in
            switch call.method {
            case "show":
                guard let args = call.arguments as? [String: Any] else {
                    result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                    return
                }
                let notifId  = args["id"] as? String ?? UUID().uuidString
                let appName  = args["appName"] as? String ?? "Android"
                let title    = args["title"] as? String ?? ""
                let body     = args["text"] as? String ?? ""
                self.showNativeNotification(id: notifId, appName: appName, title: title, body: body)
                result(nil)

            case "dismiss":
                let id = (call.arguments as? [String: Any])?["id"] as? String ?? ""
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
                result(nil)

            default:
                result(FlutterMethodNotImplemented)
            }
        }
        // Store for later use
        _notificationChannel = channel
    }

    private var _notificationChannel: FlutterMethodChannel?

    private func showNativeNotification(id: String, appName: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = "[\(appName)] \(title)"
        content.body = body
        content.sound = .default
        // Add a Dismiss action that sends dismissal back to Android via relay
        let dismissAction = UNNotificationAction(
            identifier: "DISMISS",
            title: "Dismiss on Android",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: "ANDROID_NOTIF",
            actions: [dismissAction],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
        content.categoryIdentifier = "ANDROID_NOTIF"

        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: nil // deliver immediately
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[Splurter] Notification error: \(error)")
            }
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {

    // Show notifications even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // Handle Dismiss action tap — relay back to Android
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == "DISMISS" {
            let notifId = response.notification.request.identifier
            _notificationChannel?.invokeMethod("onDismissedOnMac", arguments: ["id": notifId])
        }
        completionHandler()
    }
}

