import SwiftUI

@main
struct IlluminoteApp: App {
    @StateObject private var authVM = AuthViewModel()
    @StateObject private var toastVM = ToastViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authVM)
                .environmentObject(toastVM)
                .tint(Color("AccentColor"))
                .task { await authVM.initialize() }
        }
    }
}
