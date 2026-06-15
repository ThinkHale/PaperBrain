import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var toastVM: ToastViewModel

    var body: some View {
        ZStack(alignment: .bottom) {
            if authVM.isLoading {
                splashScreen
            } else if authVM.isSignedIn {
                MainTabView()
            } else {
                AuthView()
            }

            ToastStack()
        }
    }

    private var splashScreen: some View {
        VStack(spacing: 16) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 60))
                .foregroundStyle(.tint)
            Text("PaperBrain")
                .font(.largeTitle.bold())
            ProgressView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Main tab bar

struct MainTabView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @StateObject private var notesVM = NotesViewModel()

    var body: some View {
        TabView {
            NoteListView()
                .environmentObject(notesVM)
                .tabItem { Label("Notes", systemImage: "note.text") }

            UploadView()
                .environmentObject(notesVM)
                .tabItem { Label("Scan", systemImage: "camera.viewfinder") }

            MindMapView()
                .environmentObject(notesVM)
                .tabItem { Label("Map", systemImage: "circle.hexagongrid") }

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.circle") }
        }
        .task {
            guard let user = authVM.currentUser else { return }
            await notesVM.fetchNotes(userId: user.id)
        }
    }
}
