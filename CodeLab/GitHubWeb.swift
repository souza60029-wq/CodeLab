import SwiftUI
import WebKit

/// Página real do GitHub dentro do app (email, senha e verificação em 2 etapas).
struct GitHubWeb: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> WKWebView {
        let w = WKWebView(frame: .zero)
        w.load(URLRequest(url: url))
        return w
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct GitHubWebSheet: View {
    let url: URL
    let code: String
    @Environment(\.presentationMode) var pm

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text("Entre com email, senha e a verificação em 2 etapas. Quando pedir o código, cole este:")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                    HStack {
                        Text(code).font(.system(size: 26, weight: .bold, design: .monospaced))
                        Button("Copiar") { UIPasteboard.general.string = code }
                    }
                }
                .padding(8)
                Divider()
                GitHubWeb(url: url)
            }
            .navigationTitle("GitHub")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Fechar") { pm.wrappedValue.dismiss() } } }
        }
    }
}
