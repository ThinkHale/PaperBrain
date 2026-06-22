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
            Image("IlluminoteMark")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
            Text("Illuminote")
                .font(.largeTitle.bold())
            Text("Your thoughts. Intelligently connected.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ProgressView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.05, green: 0.11, blue: 0.16))
        .foregroundStyle(.white)
    }
}

// MARK: - Main tab bar

struct MainTabView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var toastVM: ToastViewModel
    @StateObject private var notesVM = NotesViewModel()
    @StateObject private var todosVM = TodosViewModel()
    @StateObject private var tagsVM = TagsViewModel()

    @State private var selection = 0
    @State private var previousSelection = 0
    @State private var showCapture = false

    private let captureTag = 2

    var body: some View {
        TabView(selection: $selection) {
            NoteListView()
                .environmentObject(notesVM)
                .environmentObject(tagsVM)
                .tabItem { Label("Notes", systemImage: "note.text") }
                .tag(0)

            TodoListView()
                .environmentObject(todosVM)
                .environmentObject(notesVM)
                .environmentObject(tagsVM)
                .tabItem { Label("To-Do", systemImage: "checklist") }
                .badge(todosVM.openCount)
                .tag(1)

            // Center capture button — selecting it opens the hub sheet, not a tab.
            Color.clear
                .tabItem { Label("Capture", systemImage: "plus.circle.fill") }
                .tag(captureTag)

            MindMapView()
                .environmentObject(notesVM)
                .environmentObject(tagsVM)
                .tabItem { Label("Map", systemImage: "circle.hexagongrid") }
                .tag(3)

            ProfileView()
                .environmentObject(tagsVM)
                .tabItem { Label("Profile", systemImage: "person.circle") }
                .tag(4)
        }
        .onChange(of: selection) { _, newValue in
            if newValue == captureTag {
                showCapture = true
                selection = previousSelection
            } else {
                previousSelection = newValue
            }
        }
        .sheet(isPresented: $showCapture) {
            CaptureHubView()
                .environmentObject(authVM)
                .environmentObject(toastVM)
                .environmentObject(notesVM)
                .environmentObject(todosVM)
                .environmentObject(tagsVM)
        }
        .task {
            guard let user = authVM.currentUser else { return }
            await notesVM.fetchNotes(userId: user.id)
            await todosVM.load(userId: user.id)
            await tagsVM.load(userId: user.id)
        }
    }
}
