import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var toastVM: ToastViewModel
    @StateObject private var vm = ProfileViewModel()

    var body: some View {
        NavigationStack {
            Form {
                if vm.isLoading {
                    Section { ProgressView() }
                } else {
                    displayNameSection
                    organizationSection
                    modelSection
                    handwritingSection
                    accountSection
                }
            }
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task {
                            guard let user = authVM.currentUser else { return }
                            await vm.save(userId: user.id)
                            if vm.saveSuccess { toastVM.show("Saved", style: .success) }
                        }
                    }
                    .disabled(vm.isSaving)
                }
            }
            .task {
                guard let user = authVM.currentUser else { return }
                await vm.load(userId: user.id)
            }
            .alert("Error", isPresented: .constant(vm.error != nil)) {
                Button("OK") { vm.error = nil }
            } message: {
                Text(vm.error ?? "")
            }
        }
    }

    // MARK: - Sections

    private var displayNameSection: some View {
        Section("Display Name") {
            TextField("Your name", text: $vm.displayName)
                .autocapitalization(.words)
        }
    }

    private var organizationSection: some View {
        Section("Organization") {
            NavigationLink {
                TagManagerView()
            } label: {
                Label("Tags & Categories", systemImage: "tag")
            }
        }
    }

    private var modelSection: some View {
        Section {
            Picker("OpenAI Model", selection: $vm.selectedModel) {
                ForEach(Profile.availableModels, id: \.self) { model in
                    Text(AIModel(rawValue: model)?.displayName ?? model).tag(model)
                }
            }
        } header: {
            Text("AI Model")
        } footer: {
            Text("GPT-5.4 mini is the default balance. GPT-5.4 nano is fastest. GPT-5.5 is most capable.")
                .font(.caption)
        }
    }

    private var handwritingSection: some View {
        Section {
            if let ctx = vm.profile?.handwritingContext, !ctx.isEmpty {
                Text(ctx)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No handwriting notes yet. Correcting unclear words will build your personal style guide.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Handwriting Style Guide")
        }
    }

    private var accountSection: some View {
        Section {
            if let user = authVM.currentUser {
                LabeledContent("Email", value: user.email ?? "—")
            }
            Button("Sign Out", role: .destructive) {
                Task { await authVM.signOut() }
            }
        } header: {
            Text("Account")
        }
    }
}
