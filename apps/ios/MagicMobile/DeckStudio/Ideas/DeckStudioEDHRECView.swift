import SwiftUI
import WebKit
import UniformTypeIdentifiers

/// One temporary browser per workspace. The site runs its own scripts; the app
/// injects none and never reads recommendation content or submits the deck.
@MainActor
final class DeckStudioEDHRECModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    @Published private(set) var webView: WKWebView?
    @Published private(set) var loading = false
    @Published private(set) var resolving = false
    @Published private(set) var canBack = false
    @Published private(set) var canForward = false
    @Published private(set) var currentURL: URL?
    @Published var error: String?
    @Published var externalURL: URL?
    private var navigationToken = UUID()
    private var resolutionToken = UUID()
    private var timeout: Task<Void, Never>?
    private var resolution: Task<Void, Never>?
    private func cancelResolution() { resolutionToken = UUID(); resolution?.cancel(); resolution = nil; resolving = false }
    func open(_ url: URL) {
        guard DeckStudioEDHRECPolicy.allowsEmbeddedNavigation(url) else { return }
        cancelResolution()
        if webView == nil {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
            configuration.mediaTypesRequiringUserActionForPlayback = .all
            let view = WKWebView(frame: .zero, configuration: configuration)
            view.navigationDelegate = self; view.uiDelegate = self
            view.allowsBackForwardNavigationGestures = true; view.allowsLinkPreview = false
            webView = view
        }
        error = nil; webView?.load(URLRequest(url: url, timeoutInterval: 30))
    }
    /// Only a deliberate user tap contacts Scryfall to retrieve its public EDHREC
    /// card link. No guessed commander slug, hidden EDHREC query, or deck upload.
    func openCommander(_ name: String) {
        cancelResolution(); let token = resolutionToken
        resolving = true; error = nil
        resolution = Task { [weak self] in
            do {
                guard let record = try await DeckStudioScryfallClient.shared.named(name, allowNetwork: true),
                      record.card.name == name || record.card.faces?.contains(where: { $0.name == name }) == true,
                      let url = record.card.edhrecURL, DeckStudioEDHRECPolicy.allowsEmbeddedNavigation(url) else {
                    throw DeckStudioScryfallError.invalidResponse
                }
                try Task.checkCancellation()
                guard let self, self.resolutionToken == token else { return }
                self.resolving = false; self.resolution = nil; self.open(url)
            } catch {
                guard let self, self.resolutionToken == token else { return }
                self.resolving = false; self.resolution = nil
                if !(error is CancellationError) { self.error = "Could not resolve this commander's EDHREC link. Browse EDHREC or copy the name instead. \(error.localizedDescription)" }
            }
        }
    }
    func back() { cancelResolution(); if canBack { webView?.goBack() } }
    func forward() { cancelResolution(); if canForward { webView?.goForward() } }
    func reload() { cancelResolution(); error = nil; webView?.reload() }
    func pause() { cancelResolution(); timeout?.cancel(); webView?.stopLoading(); webView?.pauseAllMediaPlayback(completionHandler: nil); loading = false }
    func clear() {
        pause(); navigationToken = UUID(); webView?.navigationDelegate = nil; webView?.uiDelegate = nil
        webView = nil; currentURL = nil; canBack = false; canForward = false; error = nil; externalURL = nil
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard self.webView === webView else { return }
        loading = true; error = nil; navigationToken = UUID(); let token = navigationToken
        timeout?.cancel()
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            guard let self, self.loading, self.navigationToken == token else { return }
            self.pause(); self.error = "The page took too long to load. Retry or open it in Safari."
        }
        update(webView)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { guard self.webView === webView else { return }; timeout?.cancel(); loading = false; update(webView) }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { guard self.webView === webView else { return }; update(webView) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error, webView) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(error, webView) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard self.webView === webView else { return }
        pause(); error = "The browser was released by iOS. Reload to continue; the previous scroll position may be lost."
    }
    private func update(_ webView: WKWebView) { currentURL = webView.url; canBack = webView.canGoBack; canForward = webView.canGoForward }
    private func failed(_ failure: Error, _ view: WKWebView) {
        guard webView === view else { return }
        timeout?.cancel(); loading = false; update(view)
        if (failure as NSError).code != NSURLErrorCancelled { error = "EDHREC could not load. Check your connection or open the page in Safari." }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard self.webView === webView, let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if navigationAction.targetFrame?.isMainFrame == false { decisionHandler(.allow); return }
        if DeckStudioEDHRECPolicy.allowsEmbeddedNavigation(url) { decisionHandler(.allow); return }
        if navigationAction.navigationType == .linkActivated && DeckStudioEDHRECPolicy.allowsExternalBrowser(url) { externalURL = url }
        else { error = "This navigation needs the full browser. Use Open in Safari." }
        decisionHandler(.cancel)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard self.webView === webView, navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url else { return nil }
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
                Menu("Commanders") {
                    ForEach(Array(Set(commanders)).sorted(), id: \.self) { name in Button(name) { model.openCommander(name) } }
                    Button("Browse on EDHREC") { model.open(DeckStudioEDHRECPolicy.browseURL) }
                }.frame(minHeight: 44)
                Button { model.clear() } label: { Image(systemName: "trash").frame(width: 44, height: 44) }.accessibilityLabel("Clear temporary browser session")
            }.padding(.horizontal, 20)
            if model.resolving { HStack { ProgressView("Resolving public link via Scryfall…"); Button("Cancel") { model.pause() } }.padding(.horizontal, 20) }
            if let error = model.error { Text(error).font(.caption).padding(.horizontal, 20) }
            if let webView = model.webView {
                HStack {
                    Button(action: model.back) { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.disabled(!model.canBack).accessibilityLabel("Previous web page")
                    Button(action: model.forward) { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.disabled(!model.canForward).accessibilityLabel("Next web page")
                    Button(action: model.reload) { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44) }.accessibilityLabel("Reload EDHREC")
                    Spacer()
                    Button("Safari", systemImage: "arrow.up.right.square") { openURL(model.currentURL ?? DeckStudioEDHRECPolicy.browseURL) }.frame(minHeight: 44)
                }.padding(.horizontal, 12)
                if model.loading { ProgressView("Loading EDHREC…") }
                DeckStudioWebSurface(webView: webView)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Explore another perspective.").font(.title2.weight(.semibold))
                        Text("Browse the actual EDHREC website, then return to Cards without losing your draft. MagicMobile does not read recommendations, fill forms, or submit your deck.")
                        Text("Commander buttons use Scryfall's public card link: Scryfall receives that name, then EDHREC and its providers receive browser requests and your IP. Website cookies stay in this temporary session. Anything you choose to paste/submit on the website is handled by that website.")
                            .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                        ForEach(Array(Set(commanders)).sorted(), id: \.self) { name in
                            Button("Browse \(name)") { model.openCommander(name) }.buttonStyle(DeckStudioButtonStyle()).disabled(model.resolving)
                        }
                        if commanders.count > 1 { Text("These open individual card/commander pages. Use EDHREC's pairing controls for combined recommendations.").font(.caption) }
                        if !commanders.isEmpty {
                            Button(copied ? "Commander names copied" : "Copy commander names", systemImage: "doc.on.doc") {
                                UIPasteboard.general.setItems([[UTType.utf8PlainText.identifier: commanders.joined(separator: "\n")]], options: [.localOnly: true]); copied = true
                            }.frame(minHeight: 44)
                        }
                        Button("Browse commanders on EDHREC") { model.open(DeckStudioEDHRECPolicy.browseURL) }.buttonStyle(DeckStudioButtonStyle(primary: false))
                        Button("Open EDHREC's Recs tool") { model.open(DeckStudioEDHRECPolicy.recsURL) }.buttonStyle(DeckStudioButtonStyle(primary: false))
                    }.padding(20)
                }
            }
        }
        .confirmationDialog("Open external website?", isPresented: Binding(get: { model.externalURL != nil }, set: { if !$0 { model.externalURL = nil } }), titleVisibility: .visible) {
            if let url = model.externalURL { Button("Open \(url.host ?? "website") in Safari") { model.externalURL = nil; openURL(url) } }
        } message: { Text("You're leaving EDHREC. MagicMobile does not automatically attach your deck to this request.") }
        .onChange(of: commanders) { _, _ in copied = false; model.pause() }
        .onDisappear { model.pause() }
    }
}
private struct DeckStudioWebSurface: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) { }
}
