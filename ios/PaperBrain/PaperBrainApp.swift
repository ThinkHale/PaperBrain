import SwiftUI

@main
struct PaperBrainApp: App {
    @StateObject private var authVM = AuthViewModel()
    @StateObject private var toastVM = ToastViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authVM)
                .environmentObject(toastVM)
                .task { await authVM.initialize() }
        }
    }
}
