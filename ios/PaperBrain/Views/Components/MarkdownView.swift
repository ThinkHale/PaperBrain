import SwiftUI
import WebKit

/// Renders a Markdown string using a lightweight WKWebView-based renderer.
/// Falls back to plain text if the input is empty.
///
/// The web view reports its content height back to SwiftUI so it occupies a
/// real, bounded frame — otherwise the transparent web view overlaps the
/// sections below it in a ScrollView.
struct MarkdownView: View {
    let text: String
    @State private var height: CGFloat = 1

    var body: some View {
        if text.isEmpty {
            Text("No content")
                .foregroundStyle(.secondary)
        } else {
            MarkdownWebView(markdown: text, height: $height)
                .frame(height: max(height, 1))
        }
    }
}

// MARK: - WKWebView renderer

private struct MarkdownWebView: UIViewRepresentable {
    let markdown: String
    @Binding var height: CGFloat

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        // Only reload when the markdown actually changes, so height callbacks
        // don't trigger an endless reload loop.
        if context.coordinator.loadedMarkdown != markdown {
            context.coordinator.loadedMarkdown = markdown
            webView.loadHTMLString(buildHTML(markdown: markdown), baseURL: nil)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: MarkdownWebView
        var loadedMarkdown: String?

        init(_ parent: MarkdownWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            measure(webView)
        }

        private func measure(_ webView: WKWebView) {
            webView.evaluateJavaScript("document.body.scrollHeight") { [weak self] result, _ in
                guard let self, let height = result as? CGFloat, height > 0 else { return }
                DispatchQueue.main.async {
                    if abs(self.parent.height - height) > 1 {
                        self.parent.height = height
                    }
                }
            }
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated, let url = action.request.url {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }

    private func buildHTML(markdown: String) -> String {
        let escaped = markdown
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
        <style>
          body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
            font-size: 15px;
            line-height: 1.6;
            color: \(isDarkMode ? "#e5e5e5" : "#1c1c1e");
            background: transparent;
            margin: 0; padding: 0;
            word-break: break-word;
          }
          h1,h2,h3 { margin-top: 1em; margin-bottom: 0.4em; }
          h1 { font-size: 1.3em; }
          h2 { font-size: 1.15em; }
          h3 { font-size: 1.05em; }
          code { background: rgba(128,128,128,0.15); padding: 2px 5px; border-radius: 4px; font-size: 0.9em; }
          pre code { display: block; padding: 12px; overflow-x: auto; }
          blockquote { border-left: 3px solid #007aff; margin: 0; padding-left: 12px; color: #666; }
          ul,ol { padding-left: 1.4em; }
          li { margin-bottom: 0.2em; }
          p { margin: 0.6em 0; }
          strong { font-weight: 600; }
        </style>
        </head>
        <body>
        <div id="content"></div>
        <script>
          document.getElementById('content').innerHTML = marked.parse(`\(escaped)`);
        </script>
        </body>
        </html>
        """
    }

    private var isDarkMode: Bool {
        UITraitCollection.current.userInterfaceStyle == .dark
    }
}
