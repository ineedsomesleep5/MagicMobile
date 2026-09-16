import SwiftUI
import WebKit
import SafariServices
import UniformTypeIdentifiers

/// Owns one temporary browser per workspace. It has no access to the deck model.
/// A normal website may use its own scripts/cookies; MagicMobile injects none.
@MainActor
final class DeckStudioEDHRECModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    @Published private(set) var webView: WKWebView?
    @Published private(set) var loading = false
    @Published private(set) var canBack = false
    @Published private(set) var canForward = false
    @Published private(set) var currentURL: URL?
    @Published var error: String?
    @Published var externalURL: URL?
    private var navigationToken = UUID()
    private var timeout: Task<Void, Never>?

    func open(_ url: URL) {
        guard DeckStudioEDHRECPolicy.allowsEmbeddedNavigation(url) else { return }
        if webView == nil {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
            configuration.mediaTypesRequiringUserActionForPlayback = .all
            let view = WKWebView(frame: .zero, configuration: configuration)
            view.navigationDelegate = self; view.uiDelegate = self
            view.allowsBackForwardNavigationGestures = true
            view.allowsLinkPreview = false
            webView = view
        }
        error = nil
        webView?.load(URLRequest(url: url, timeoutInterval: 30))
    }
    func back() { if canBack { webView?.goBack() } }
    func forward() { if canForward { webView?.goForward() } }
    func reload() { error = nil; webView?.reload() }
    func pause() { timeout?.cancel(); webView?.stopLoading(); webView?.pauseAllMediaPlayback(completionHandler: nil); loading = false }
    func clear() {
        pause(); webView?.navigationDelegate = nil; webView?.uiDelegate = nil
        webView = nil; currentURL = nil; canBack = false; canForward = false
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loading = true; error = nil; navigationToken = UUID()
        let token = navigationToken
        timeout?.cancel()
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            guard let self, self.loading, self.navigationToken == token else { return }
            self.pause(); self.error = "The page took too long to load. Retry or open it in Safari."
        }
        update(webView)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { timeout?.cancel(); loading = false; update(webView) }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { update(webView) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error, webView) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(error, webView) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        pause(); error = "The browser was released by iOS. Reload to continue; its previous scroll position may be lost."
    }
    private func update(_ webView: WKWebView) { currentURL = webView.url; canBack = webView.canGoBack; canForward = webView.canGoForward }
    private func failed(_ failure: Error, _ view: WKWebView) {
        timeout?.cancel(); loading = false; update(view)
        if (failure as NSError).code != NSURLErrorCancelled { error = "EDHREC could not load. Check your connection or open the page in Safari." }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        // Ordinary third-party subframes are left to WebKit. This is not ad blocking.
        if navigationAction.targetFrame?.isMainFrame == false { decisionHandler(.allow); return }
        if DeckStudioEDHRECPolicy.allowsEmbeddedNavigation(url) { decisionHandler(.allow); return }
        if navigationAction.navigationType == .linkActivated && DeckStudioEDHRECPolicy.allowsExternalBrowser(url) { externalURL = url }
        else { error = "This navigation needs the full browser. Use Open in Safari; no deck data was submitted by MagicMobile." }
        decisionHandler(.cancel)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url else { return nil }
        if DeckStudioEDHRECPolicy.allowsEmbeddedNavigation(url) { open(url) }
        else if DeckStudioEDHRECPolicy.allowsExternalBrowser(url) { externalURL = url }
        return nil
    }
}

struct DeckStudioEDHRECPanel: View {
    @ObservedObject var model: DeckStudioEDHRECModel
    let commanders: [String]
    @Environment(\.openURL) private var openURL
    @State private var copied = false
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("EDHREC — web").font(.subheadline.weight(.semibold))
                Spacer()
                Button { model.clear() } label: { Image(systemName: "trash").frame(width: 44, height: 44) }
                    .accessibilityLabel("Close browser and clear its temporary session")
            }.padding(.horizontal, 20)
            if let webView = model.webView {
                HStack {
                    Button(action: model.back) { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.disabled(!model.canBack).accessibilityLabel("Previous web page")
                    Button(action: model.forward) { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.disabled(!model.canForward).accessibilityLabel("Next web page")
                    Button(action: model.reload) { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44) }.accessibilityLabel("Reload EDHREC")
                    Spacer()
                    Button("Safari", systemImage: "arrow.up.right.square") { openURL(model.currentURL ?? DeckStudioEDHRECPolicy.browseURL) }.frame(minHeight: 44)
                }.padding(.horizontal, 12)
                if model.loading { ProgressView("Loading EDHREC…") }
                if let error = model.error { Text(error).font(.caption).padding(.horizontal, 20) }
                DeckStudioWebSurface(webView: webView)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Explore another perspective.").font(.system(.title2, design: .serif).weight(.semibold))
                        Text("Browse the actual EDHREC website, then return to Cards without losing your draft. MagicMobile does not read recommendations, fill forms, or upload your deck.")
                        Text("The website and its providers receive your IP address and browser requests. Cookies stay in this temporary browser session; clear the session when finished.")
                            .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                        if !commanders.isEmpty {
                            Text(commanders.joined(separator: " + ")).font(.headline)
                            Button(copied ? "Commander names copied" : "Copy commander names", systemImage: "doc.on.doc") {
                                UIPasteboard.general.setItems([[UTType.utf8PlainText.identifier: commanders.joined(separator: "\n")]], options: [.localOnly: true]); copied = true
                            }.frame(minHeight: 44)
                        }
                        Button("Browse commanders on EDHREC") { model.open(DeckStudioEDHRECPolicy.browseURL) }
                            .buttonStyle(DeckStudioButtonStyle())
                        Button("Open EDHREC’s Recs tool") { model.open(DeckStudioEDHRECPolicy.recsURL) }
                            .buttonStyle(DeckStudioButtonStyle(primary: false))
                        Text("This first version opens EDHREC’s normal commander browser rather than guessing a commander URL. Paste the copied names on the website yourself.")
                            .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                    }.padding(20)
                }
            }
        }
        .confirmationDialog("Open external website?", isPresented: Binding(get: { model.externalURL != nil }, set: { if !$0 { model.externalURL = nil } }), titleVisibility: .visible) {
            if let url = model.externalURL { Button("Open \(url.host ?? "website") in Safari") { model.externalURL = nil; openURL(url) } }
        } message: { Text("You’re leaving EDHREC. MagicMobile will not share your deck with this site.") }
        .onChange(of: commanders) { _, _ in copied = false }
    }
}

private struct DeckStudioWebSurface: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) { }
}
