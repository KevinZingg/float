import AppKit
import WebKit

/// Browser-style permissions and dialogs for one web card: camera/mic prompts (remembered per site),
/// file pickers and JS alert/confirm/prompt.
@MainActor
final class WebPermissions {
    let prompt = PromptView()

    init(host: NSView) {
        prompt.install(in: host)
    }

    func cancelAll() { prompt.cancelAll() }

    // MARK: - Camera / microphone

    func requestMediaCapture(
        origin: WKSecurityOrigin, type: WKMediaCaptureType, decision: @escaping @MainActor (WKPermissionDecision) -> Void
    ) {
        let site = SitePermissions.site(protocol: origin.protocol, host: origin.host, port: origin.port)
        if URLInput.isLocal(host: origin.host) { return decision(.grant) }
        if let remembered = SitePermissions.decision(site: site, type: type.rawValue) {
            return decision(remembered ? .grant : .deny)
        }
        prompt.enqueue(.init(
            message: "\(site.label) wants to use your \(SitePermissions.describe(type))",
            buttons: ["Allow", "Don’t Allow"], defaultIndex: 0, cancelIndex: 1
        ) { index, _ in
            let allowed = index == 0
            SitePermissions.remember(allowed, site: site, type: type.rawValue)
            decision(allowed ? .grant : .deny)
        })
    }

    // MARK: - File upload

    func runOpenPanel(parameters: WKOpenPanelParameters, in window: NSWindow?, completion: @escaping @MainActor ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            MainActor.assumeIsolated { completion(response == .OK ? panel.urls : nil) }
        }
        if let window { panel.beginSheetModal(for: window, completionHandler: finish) } else { panel.begin(completionHandler: finish) }
    }

    // MARK: - JS dialogs

    func alert(_ message: String, from origin: String, completion: @escaping @MainActor () -> Void) {
        prompt.enqueue(.init(message: "\(origin) says:\n\(message)", buttons: ["OK"], defaultIndex: 0, cancelIndex: 0) { _, _ in
            completion()
        })
    }

    func confirm(_ message: String, from origin: String, completion: @escaping @MainActor (Bool) -> Void) {
        prompt.enqueue(.init(message: "\(origin) says:\n\(message)", buttons: ["OK", "Cancel"], defaultIndex: 0, cancelIndex: 1) {
            index, _ in completion(index == 0)
        })
    }

    func textInput(_ message: String, default text: String?, from origin: String, completion: @escaping @MainActor (String?) -> Void) {
        prompt.enqueue(.init(
            message: "\(origin) says:\n\(message)", buttons: ["OK", "Cancel"], defaultIndex: 0, cancelIndex: 1,
            textDefault: text ?? ""
        ) { index, value in completion(index == 0 ? value : nil) })
    }
}

/// WKUIDelegate permission and dialog callbacks, forwarded to the card's `WebPermissions`.
extension WebCard {
    func webView(
        _ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
        decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void
    ) {
        permissions.requestMediaCapture(origin: origin, type: type, decision: decisionHandler)
    }

    func webView(
        _ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor ([URL]?) -> Void
    ) {
        permissions.runOpenPanel(parameters: parameters, in: webView.window, completion: completionHandler)
    }

    func webView(
        _ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor () -> Void
    ) {
        permissions.alert(message, from: frame.securityOrigin.host, completion: completionHandler)
    }

    func webView(
        _ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (Bool) -> Void
    ) {
        permissions.confirm(message, from: frame.securityOrigin.host, completion: completionHandler)
    }

    func webView(
        _ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
        initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (String?) -> Void
    ) {
        permissions.textInput(prompt, default: defaultText, from: frame.securityOrigin.host, completion: completionHandler)
    }
}

/// Per-site camera/mic decisions, remembered in UserDefaults.
enum SitePermissions {
    struct Site: Equatable {
        let key: String
        /// What the prompt shows: the host, plus the port if it isn't the default.
        let label: String
    }

    private static let defaultsKey = "sitePermissions"

    static func site(protocol scheme: String, host: String, port: Int) -> Site {
        let defaultPort = (scheme == "https" && port == 443) || (scheme == "http" && port == 80) || port == 0
        let label = defaultPort ? host : "\(host):\(port)"
        return Site(key: "\(scheme)://\(label)", label: label)
    }

    static func describe(_ type: WKMediaCaptureType) -> String {
        switch type {
        case .camera: "camera"
        case .microphone: "microphone"
        case .cameraAndMicrophone: "camera and microphone"
        @unknown default: "camera or microphone"
        }
    }

    static func decision(site: Site, type: Int) -> Bool? {
        (UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Bool])?["\(site.key)|\(type)"]
    }

    static func remember(_ allowed: Bool, site: Site, type: Int) {
        var all = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Bool] ?? [:]
        all["\(site.key)|\(type)"] = allowed
        UserDefaults.standard.set(all, forKey: defaultsKey)
    }

    static func resetAll() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}
