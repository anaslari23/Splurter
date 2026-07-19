import Foundation
import Network
import FlutterMacOS

class DiscoveryHandler {
    private let channel: FlutterMethodChannel
    private let advertiserProvider: () -> NWListener?
    private var browser: NWBrowser?

    init(channel: FlutterMethodChannel, advertiser: @escaping () -> NWListener?) {
        self.channel = channel
        self.advertiserProvider = advertiser
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "advertise":
            result(nil)
        case "stopAdvertising":
            advertiserProvider()?.cancel()
            result(nil)
        case "browse":
            guard let serviceType = (call.arguments as? [String: Any])?["serviceType"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "serviceType required", details: nil))
                return
            }
            startBrowsing(serviceType: serviceType)
            result(nil)
        case "stopBrowsing":
            browser?.cancel()
            browser = nil
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func startBrowsing(serviceType: String) {
        let bonjourType = serviceType.hasSuffix(".") ? serviceType : serviceType + ".local."
        let parameters = NWParameters.tcp
        let browser = NWBrowser(
            for: NWBrowser.Descriptor.bonjour(type: bonjourType, domain: nil),
            using: parameters
        )

        browser.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                print("Browse failed: \(error)")
            }
        }

        browser.start(queue: .main)
        self.browser = browser
    }
}