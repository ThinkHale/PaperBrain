import SwiftUI
import WebKit

/// Renders a Markdown string using a lightweight WKWebView-based renderer.
/// Falls back to plain text if the input is empty.
struct MarkdownView: View {
    let text: String

    var body: some View {
        if text.isEmpty {
            Text("No content")
                .foregroundStyle(.secondary)
        } else {
            MarkdownWebView(markdown: text)
        }
    }
}

// MARK: - WKWebView renderer

private struct MarkdownWebView: UIViewRepresentable {
    let markdown: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let html = buildHTML(markdown: markdown)
        webView.loadHTMLString(html, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Resize WebView to fit content height
            webView.evaluateJavaScript("document.body.scrollHeight") { result, _ in
                if let height = result as? CGFloat {
                    webView.frame.size.height = height
                }
            }
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Allow initial load; open external links in Safari
            if action.navigationType == .linkActivated, let url = action.request.url {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }

    private func buildHTML(markdown: String) -> String {
        // Escape for inclusion in JS string
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

// MARK: - Dynamic height wrapper

/// Wraps MarkdownWebView in a dynamically-sized frame.
struct MarkdownBlock: View {
    let text: String
    @State private var height: CGFloat = 200

    var body: some View {
        MarkdownWebView(markdown: text)
            .frame(height: height)
            .onPreferenceChange(MarkdownHeightKey.self) { height = $0 }
    }
}

private struct MarkdownHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 200
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
