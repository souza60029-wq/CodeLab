import SwiftUI
import UIKit

@main
struct CodeLabApp: App {
    init() {
        // toque mais rápido: os botões dentro de listas e rolagens respondem na hora
        UIScrollView.appearance().delaysContentTouches = false
    }

    var body: some Scene {
        WindowGroup { RootView() }
    }
}
