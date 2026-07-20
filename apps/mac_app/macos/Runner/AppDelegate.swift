import Cocoa
import FlutterMacOS
import Network
import Foundation

@main
class AppDelegate: FlutterAppDelegate {
    private var clipboardMonitor: ClipboardMonitor?
    private var browser: NWBrowser?
    private var advertiser: NWListener?
    private var fileHandler: FileHandler?
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    override func applicationDidFinishLaunching(_ notification: Notification) {
        // Set as menu bar accessory so the app lives without a dock icon
        NSApp.setActivationPolicy(.accessory)

        setupPlatformChannels()
        startAdvertiser()
        startBrowser()
        setupStatusItem()
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
    }

    // MARK: - Menu Bar Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "antenna.radiowaves.left.and.right", accessibilityDescription: "Splurter")
            button.action = #selector(handleStatusClick)
            button.target = self
        }

        // Build a minimal popover menu (since the Flutter UI is small and lives in a window)
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Splurter", action: #selector(showMainWindow), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem?.menu = menu
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
}
