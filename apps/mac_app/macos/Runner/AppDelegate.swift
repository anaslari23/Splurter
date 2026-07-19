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
        let messenger = mainFlutterWindow?.engine.binaryMessenger
            ?? NSApplication.shared.windows.first?.contentViewController?.representedObject as? FlutterViewController
        let controller = mainFlutterWindow?.rootViewController as? FlutterViewController
            ?? NSApplication.shared.windows.first?.contentViewController as? FlutterViewController

        let binaryMessenger: FlutterBinaryMessenger
        if let bm = messenger {
            binaryMessenger = bm
        } else if let c = controller {
            binaryMessenger = c.engine.binaryMessenger
        } else {
            return
        }

        // Clipboard
        let clipboardChannel = FlutterMethodChannel(
            name: "splurter/clipboard",
            binaryMessenger: binaryMessenger
        )
        clipboardMonitor = ClipboardMonitor(channel: clipboardChannel)

        // Discovery
        let discoveryChannel = FlutterMethodChannel(
            name: "splurter/discovery",
            binaryMessenger: binaryMessenger
        )
        let discoveryHandler = DiscoveryHandler(channel: discoveryChannel)
        discoveryChannel.setMethodCallHandler(discoveryHandler.handle)

        // File
        let fileChannel = FlutterMethodChannel(
            name: "splurter/file",
            binaryMessenger: binaryMessenger
        )
        fileHandler = FileHandler(channel: fileChannel)
        fileChannel.setMethodCallHandler { [weak self] call, result in
            self?.fileHandler?.handle(call, result: result)
        }

        // Network
        let networkChannel = FlutterMethodChannel(
            name: "splurter/network",
            binaryMessenger: binaryMessenger
        )
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
        let parameters = NWParameters.tcp()
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
        service.publish(options: [.daemon, .noAutoRename])
    }

    private func startBrowser() {
        let parameters = NWParameters.tcp()
        parameters.allowLocalEndpointReuse = true

        browser = NWBrowser(for: .bonjour(type: "_splurter._tcp.", domain: nil), using: parameters)
        browser?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready(let results):
                for result in results {
                    self?.handleBrowseResult(result)
                }
            case .failed(let error):
                print("Browse failed: \(error)")
            default:
                break
            }
        }
        browser?.start(queue: .main)
    }

    private func handleBrowseResult(_ result: NWBrowser.Result) {
        guard case .service(let service, let metadata) = result.endpoint else { return }
        let hostname = metadata.hostname
        let port = metadata.port

        var ip = hostname
        if let host = NWEndpoint.Host(hostname), let resolved = host.rawValue {
            ip = resolved
        }

        let binaryMessenger: FlutterBinaryMessenger? = {
            if let bm = mainFlutterWindow?.engine.binaryMessenger { return bm }
            return NSApplication.shared.windows.first?.contentViewController?.representedObject as? FlutterViewController
        }()?.engine.binaryMessenger

        guard let messenger = binaryMessenger ?? (mainFlutterWindow?.rootViewController as? FlutterViewController)?.engine.binaryMessenger else { return }

        let channel = FlutterMethodChannel(
            name: "splurter/discovery",
            binaryMessenger: messenger
        )
        channel.invokeMethod("onServiceFound", [
            "id": service.name,
            "name": service.name,
            "address": ip,
            "port": port,
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
