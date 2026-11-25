//
//  RedlineEditorSheet.swift
//  Sellside Mobile
//

import SwiftUI
import WebKit

/// "Review Redlines" — the member's proposed NDA changes. On the web this is
/// Formable's hosted editor in an iframe (formable.service.ts
/// `embedRedlineDocument`), not an Axial screen, so mobile hosts the same
/// editor rather than rebuilding it.
///
/// The editor talks by `postMessage` to its parent. Loaded top-level here,
/// those messages land on its own window, so a script relays them to the
/// app: Saved submits the redline (`POST …/submit-redline`, polled until the
/// redline stops pending) and reloads the members; Closed or Canceled just
/// leaves. Closing asks the editor first (`onModalClosed`), so it can warn
/// about unsaved changes — `deferCloseToIframe`.
struct RedlineEditorSheet: View {
    let projectId: String
    let deal: SellsideDeal

    @Environment(ProjectDashboardStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var url: URL?
    @State private var phase: Phase = .loading
    @State private var closeRequest = 0
    @State private var error: String?

    enum Phase: Equatable { case loading, editing, submitting }

    var body: some View {
        NavigationStack {
            ZStack {
                if let url {
                    FormableWebView(url: url, closeRequest: closeRequest, onEvent: handle)
                        .ignoresSafeArea(edges: .bottom)
                }
                if phase != .editing {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(phase == .submitting ? "Submitting your redline…" : "Opening the NDA…")
                            .font(.subheadline)
                            .foregroundStyle(AxialColor.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AxialColor.layer2)
                }
            }
            .navigationTitle("Redline NDA")
            .navigationSubtitle(deal.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) {
                        // Let the editor confirm unsaved changes; if it
                        // doesn't answer, leave anyway.
                        guard phase == .editing else { dismiss(); return }
                        closeRequest += 1
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            if phase == .editing { dismiss() }
                        }
                    }
                    .disabled(phase == .submitting)
                }
            }
        }
        .interactiveDismissDisabled()
        .task { await open() }
        .alert("Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil; dismiss() } }),
               presenting: error) { _ in
            Button("OK", role: .cancel) {}
        } message: { Text($0) }
    }

    private func open() async {
        do {
            url = try await store.redlineEditorURL(dealId: deal.id)
        } catch {
            self.error = "There was an error opening the redline document."
        }
    }

    /// `formable-modal.component.ts`'s message types.
    private func handle(_ type: String) {
        switch type {
        case "loaded":
            if phase == .loading { phase = .editing }
        case "onRedlineEditorSaved":
            phase = .submitting
            Task {
                do {
                    try await store.submitRedline(dealId: deal.id, on: projectId)
                    Haptics.success()
                    dismiss()
                } catch {
                    Haptics.error()
                    self.error = error.localizedDescription
                }
            }
        case "onRedlineEditorError":
            error = "There was an error opening the redline document."
        case "onRedlineEditorClosed", "onEditorCanceled", "userRequestedToSign":
            // Signing is the buyer's path; for the seller it's just done.
            Task { await store.load(id: projectId) }
            dismiss()
        default:
            break
        }
    }
}

/// A `WKWebView` that relays the page's `postMessage` events by `type`, and
/// can post `onModalClosed` back in.
private struct FormableWebView: UIViewRepresentable {
    let url: URL
    let closeRequest: Int
    let onEvent: (String) -> Void

    /// `^https://((www|app)\.)?formabledocs\.com$` — formable.constants.ts.
    static func isTrusted(_ origin: String) -> Bool {
        origin.range(of: #"^https://((www|app)\.)?formabledocs\.com$"#, options: .regularExpression) != nil
    }

    func makeCoordinator() -> Coordinator { Coordinator(onEvent: onEvent) }

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        // Relay what the editor posts "to its parent" — its own window here.
        let relay = """
        window.addEventListener('message', function (event) {
            var type = event.data && event.data.type;
            if (typeof type === 'string') {
                window.webkit.messageHandlers.formable.postMessage({ type: type });
            }
        });
        """
        controller.addUserScript(WKUserScript(source: relay, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        controller.add(context.coordinator, name: "formable")
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onEvent = onEvent
        if closeRequest != context.coordinator.lastCloseRequest {
            context.coordinator.lastCloseRequest = closeRequest
            webView.evaluateJavaScript("window.postMessage({ type: 'onModalClosed' }, '*');")
        }
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var onEvent: (String) -> Void
        var lastCloseRequest = 0

        init(onEvent: @escaping (String) -> Void) {
            self.onEvent = onEvent
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            // Only the editor's own pages are listened to, as on the web.
            guard FormableWebView.isTrusted(message.frameInfo.securityOrigin.originString) else { return }
            onEvent(type)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onEvent("loaded")
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onEvent("onRedlineEditorError")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onEvent("onRedlineEditorError")
        }
    }
}

private extension WKSecurityOrigin {
    var originString: String {
        port == 0 ? "\(`protocol`)://\(host)" : "\(`protocol`)://\(host):\(port)"
    }
}
