import AppKit
import WebKit

/// A web preview: WKWebView at a virtual viewport width, zoomed to the card width.
@MainActor
final class WebCard: NSObject, CardContent {
    let kind = CardKind.web
    private let host = ResizeObservingView()
    private let webView: FloatWebView
    private let toast = ToastView()
    private let downloads = DownloadManager()
    /// Camera/mic prompts, file pickers and JS dialogs (see WebPermissions.swift).
    private(set) var permissions: WebPermissions!
    private let urlField = URLField()
    private let viewportMenu = NSPopUpButton(frame: .zero, pullsDown: false)
    private let controls = NSStackView()
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private var retryTimer: Timer?
    private var observations: [NSKeyValueObservation] = []
    private(set) var title = "Preview"
    private(set) var viewport = Viewport.desktop
    var onTitleChange: ((String) -> Void)?
    var onRequestClose: (() -> Void)?
    /// Asks the card to take a content aspect ratio (nil = free).
    var onSuggestAspect: ((CGFloat?) -> Void)?
    /// Asks for a new card next to this one (popup, target=_blank, ⌘-click), with an optional size hint.
    var onOpenCard: ((WebCard, CGSize?) -> Void)?
    /// Set by "Open in Default Browser" so the popup WebKit is about to request goes to the system browser.
    private var nextPopupToBrowser = false

    var view: NSView { host }
    var accessory: NSView? { controls }

    convenience init(url input: String = Settings.defaultURL) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.preferences.isElementFullscreenEnabled = true
        self.init(configuration: config)
        load(input)
    }

    /// WebKit popups must use the configuration it provides (keeps window.opener), and WebKit loads them itself.
    init(configuration: WKWebViewConfiguration) {
        webView = FloatWebView(frame: .zero, configuration: configuration)
        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.onOpenInDefaultBrowser = { [weak self] in self?.nextPopupToBrowser = true }
        webView.isInspectable = true
        webView.allowsBackForwardNavigationGestures = true
        webView.autoresizingMask = [.width, .height]
        host.addSubview(webView)
        buildErrorLabel()
        toast.install(in: host)
        permissions = WebPermissions(host: host)
        downloads.onEvent = { [weak self] in self?.downloadEvent($0) }
        host.onResize = { [weak self] in self?.updateZoom() }

        buildControls()
        observations = [
            webView.observe(\.title) { [weak self] web, _ in
                MainActor.assumeIsolated { self?.titleChanged(web.title) }
            },
            webView.observe(\.url) { [weak self] web, _ in
                MainActor.assumeIsolated { self?.urlChanged(web.url) }
            },
        ]
    }

    func load(_ input: String) {
        guard let url = URLInput.url(from: input) else { NSSound.beep(); return }
        urlField.stringValue = url.absoluteString
        load(url)
    }

    private func load(_ url: URL) {
        retryTimer?.invalidate()
        webView.load(URLRequest(url: url))
    }

    // MARK: - Error state

    private func buildErrorLabel() {
        errorLabel.font = .systemFont(ofSize: 13)
        errorLabel.textColor = .secondaryLabelColor
        errorLabel.alignment = .center
        errorLabel.isHidden = true
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(errorLabel)
        NSLayoutConstraint.activate([
            errorLabel.centerXAnchor.constraint(equalTo: host.centerXAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: host.centerYAnchor),
            errorLabel.widthAnchor.constraint(lessThanOrEqualTo: host.widthAnchor, constant: -32),
        ])
    }

    /// Replaces the blank page with a message. A local dev server that isn't up yet is retried.
    private func showError(_ error: Error, for url: URL?) {
        let nsError = error as NSError
        // Cancelled, or interrupted because the response turned into a download: not an error to show.
        let interrupted = nsError.domain == "WebKitErrorDomain" && nsError.code == 102
        guard nsError.code != NSURLErrorCancelled, !interrupted else { return }
        NSLog("Float: load failed for %@: %@", url?.absoluteString ?? "?", nsError.description)
        let host = url?.host ?? "page"
        if nsError.code == NSURLErrorCannotConnectToHost, let url, URLInput.isLocal(url) {
            errorLabel.stringValue = "Nothing on :\(url.port.map(String.init) ?? host) yet… retrying"
            retryTimer?.invalidate()
            retryTimer = Timer.scheduledTimer(withTimeInterval: Settings.localRetryInterval, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.load(url) }
            }
        } else {
            errorLabel.stringValue = "Couldn’t reach \(host)\n\(nsError.localizedDescription)"
        }
        errorLabel.isHidden = false
        webView.isHidden = true
    }

    private func clearError() {
        errorLabel.isHidden = true
        webView.isHidden = false
    }

    /// Mirrors navigation into the field, but never clobbers what the user is typing, and keeps
    /// the attempted URL visible when a failed load leaves the web view without one.
    private func urlChanged(_ url: URL?) {
        guard let url, urlField.currentEditor() == nil else { return }
        urlField.stringValue = url.absoluteString
    }

    private func titleChanged(_ newTitle: String?) {
        guard let newTitle, !newTitle.isEmpty else { return }
        title = newTitle
        onTitleChange?(newTitle)
    }

    /// Skipped until the card has a width, otherwise a new card briefly lays out at a ~0 zoom.
    private func updateZoom() {
        guard host.bounds.width >= 1 else { return }
        webView.pageZoom = viewport.pageZoom(forCardWidth: host.bounds.width)
    }

    func setViewport(_ viewport: Viewport) {
        self.viewport = viewport
        viewportMenu.selectItem(withTitle: viewport.rawValue)
        updateZoom()
        onSuggestAspect?(viewport.suggestedAspect)
    }

    // MARK: - Links and downloads

    private func openInNewCard(_ url: URL) {
        let card = WebCard(url: url.absoluteString)
        card.setViewport(viewport)
        onOpenCard?(card, nil)
    }

    private func downloadEvent(_ event: DownloadManager.Event) {
        switch event {
        case .progress(let name, let fraction):
            toast.show("Downloading \(name) · \(Int(fraction * 100))%", sticky: true)
        case .finished(let url):
            NSLog("Float: downloaded %@", url.path)
            toast.show("Downloaded \(url.lastPathComponent) · Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        case .failed(let name, let error):
            NSLog("Float: download of %@ failed: %@", name, "\(error)")
            toast.show("Couldn’t download \(name) · \(error.localizedDescription)")
        }
    }

    // MARK: - Chrome controls

    private func buildControls() {
        let back = button("chevron.left", "Back", #selector(goBack))
        let forward = button("chevron.right", "Forward", #selector(goForward))
        let reloadButton = button("arrow.clockwise", "Reload", #selector(reloadClicked))

        urlField.font = .systemFont(ofSize: 11)
        urlField.bezelStyle = .roundedBezel
        urlField.controlSize = .small
        urlField.placeholderString = "localhost:3000"
        urlField.lineBreakMode = .byTruncatingTail
        urlField.target = self
        urlField.action = #selector(urlEntered)
        urlField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        urlField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        viewportMenu.addItems(withTitles: Viewport.allCases.map(\.rawValue))
        viewportMenu.controlSize = .small
        viewportMenu.font = .systemFont(ofSize: 11)
        viewportMenu.isBordered = false
        viewportMenu.target = self
        viewportMenu.action = #selector(viewportPicked)

        controls.orientation = .horizontal
        controls.spacing = 2
        controls.alignment = .centerY
        controls.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        for v in [back, forward, reloadButton, urlField, viewportMenu] { controls.addArrangedSubview(v) }
    }

    private func button(_ symbol: String, _ label: String, _ action: Selector) -> NSButton {
        let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: label)!, target: self, action: action)
        b.isBordered = false
        b.contentTintColor = .secondaryLabelColor
        b.widthAnchor.constraint(equalToConstant: 20).isActive = true
        return b
    }

    @objc private func goBack() { webView.goBack() }
    @objc private func goForward() { webView.goForward() }
    @objc private func reloadClicked() { reload() }
    @objc private func urlEntered() { load(urlField.stringValue); focus() }

    @objc private func viewportPicked() {
        if let title = viewportMenu.titleOfSelectedItem, let v = Viewport(rawValue: title) { setViewport(v) }
    }

    // MARK: - CardContent

    func focus() { webView.window?.makeFirstResponder(webView) }
    func reload() { webView.reload() }

    func zoom(by step: Int) {
        let all = Viewport.allCases
        guard let i = all.firstIndex(of: viewport) else { return }
        // Bigger text = narrower virtual viewport.
        setViewport(all[min(max(i + step, 0), all.count - 1)])
    }

    func close() {
        permissions.cancelAll()
        retryTimer?.invalidate()
        observations.removeAll()
        webView.stopLoading()
        webView.removeFromSuperview()
    }
}

extension WebCard: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { clearError() }

    /// Re-applied per navigation in case WebKit resets zoom when it swaps web-content processes.
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { updateZoom() }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showError(error, for: failingURL(error) ?? webView.url)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showError(error, for: failingURL(error) ?? webView.url)
    }

    private func failingURL(_ error: Error) -> URL? {
        (error as NSError).userInfo[NSURLErrorFailingURLErrorKey] as? URL
    }

    func webView(
        _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        let url = action.request.url
        let decision = WebNavigation.action(
            for: url, modifiers: action.modifierFlags,
            isLinkClick: action.navigationType == .linkActivated, shouldDownload: action.shouldPerformDownload)
        switch decision {
        case .allow: decisionHandler(.allow)
        case .download: decisionHandler(.download)
        case .newCard:
            if let url { openInNewCard(url) }
            decisionHandler(.cancel)
        case .defaultBrowser, .external:
            if let url { NSWorkspace.shared.open(url) }
            decisionHandler(.cancel)
        }
    }

    func webView(
        _ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
        decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void
    ) {
        let disposition = (response.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition")
        let download = WebNavigation.shouldDownload(canShowMIMEType: response.canShowMIMEType, contentDisposition: disposition)
        decisionHandler(download ? .download : .allow)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        downloads.track(download)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        downloads.track(download)
    }
}

extension WebCard: WKUIDelegate {
    /// target=_blank, window.open() and "Open Link in New Window" become a new card next to this one.
    func webView(
        _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
        for action: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if nextPopupToBrowser {
            nextPopupToBrowser = false
            if let url = action.request.url { NSWorkspace.shared.open(url) }
            return nil
        }
        let card = WebCard(configuration: configuration)
        card.setViewport(viewport)
        let size = WebNavigation.popupSize(
            width: windowFeatures.width.map { CGFloat($0.doubleValue) },
            height: windowFeatures.height.map { CGFloat($0.doubleValue) })
        onOpenCard?(card, size)
        return card.webView
    }

    func webViewDidClose(_ webView: WKWebView) {
        onRequestClose?()
    }
}

/// Adds "Open in Default Browser" next to WebKit's "Open Link in New Window".
private final class FloatWebView: WKWebView {
    var onOpenInDefaultBrowser: (() -> Void)?

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        guard let i = menu.items.firstIndex(where: { $0.identifier?.rawValue == "WKMenuItemIdentifierOpenLinkInNewWindow" })
        else { return }
        menu.items[i].title = "Open Link in New Card"
        let item = NSMenuItem(title: "Open in Default Browser", action: #selector(openInDefaultBrowser(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = menu.items[i]
        menu.insertItem(item, at: i + 1)
    }

    /// Reuses WebKit's own "open in new window" to resolve the link, flagged to go to the system browser.
    @objc private func openInDefaultBrowser(_ sender: NSMenuItem) {
        guard let original = sender.representedObject as? NSMenuItem, let action = original.action else { return }
        onOpenInDefaultBrowser?()
        NSApp.sendAction(action, to: original.target, from: original)
    }
}

/// Takes focus on the first click even when Float isn't active yet; otherwise that click only
/// focuses the card and the typed URL goes to the page instead.
private final class URLField: NSTextField {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Reports size changes so the page zoom can follow the card width.
private final class ResizeObservingView: NSView {
    var onResize: (() -> Void)?

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        onResize?()
    }
}
