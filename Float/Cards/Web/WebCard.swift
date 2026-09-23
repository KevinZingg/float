import AppKit
import WebKit

/// A web preview: WKWebView at a virtual viewport width, zoomed to the card width.
@MainActor
final class WebCard: NSObject, CardContent {
    let kind = CardKind.web
    private let host = ResizeObservingView()
    private let webView: WKWebView
    private let urlField = NSTextField()
    private let viewportMenu = NSPopUpButton(frame: .zero, pullsDown: false)
    private let controls = NSStackView()
    private var observations: [NSKeyValueObservation] = []
    private(set) var title = "Preview"
    private(set) var viewport = Viewport.desktop
    var onTitleChange: ((String) -> Void)?
    var onRequestClose: (() -> Void)?
    /// Asks the card to take a content aspect ratio (nil = free).
    var onSuggestAspect: ((CGFloat?) -> Void)?

    var view: NSView { host }
    var accessory: NSView? { controls }

    init(url input: String = Settings.defaultURL) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()

        webView.isInspectable = true
        webView.allowsBackForwardNavigationGestures = true
        webView.autoresizingMask = [.width, .height]
        host.addSubview(webView)
        host.onResize = { [weak self] in self?.updateZoom() }

        buildControls()
        observations = [
            webView.observe(\.title) { [weak self] web, _ in
                MainActor.assumeIsolated { self?.titleChanged(web.title) }
            },
            webView.observe(\.url) { [weak self] web, _ in
                MainActor.assumeIsolated { self?.urlField.stringValue = web.url?.absoluteString ?? "" }
            },
        ]
        load(input)
    }

    func load(_ input: String) {
        guard let url = URLInput.url(from: input) else { NSSound.beep(); return }
        urlField.stringValue = url.absoluteString
        webView.load(URLRequest(url: url))
    }

    private func titleChanged(_ newTitle: String?) {
        guard let newTitle, !newTitle.isEmpty else { return }
        title = newTitle
        onTitleChange?(newTitle)
    }

    private func updateZoom() {
        webView.pageZoom = viewport.pageZoom(forCardWidth: host.bounds.width)
    }

    func setViewport(_ viewport: Viewport) {
        self.viewport = viewport
        viewportMenu.selectItem(withTitle: viewport.rawValue)
        updateZoom()
        onSuggestAspect?(viewport.suggestedAspect)
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
        observations.removeAll()
        webView.stopLoading()
        webView.removeFromSuperview()
    }
}

/// Reports size changes so the page zoom can follow the card width.
private final class ResizeObservingView: NSView {
    var onResize: (() -> Void)?

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        onResize?()
    }
}
