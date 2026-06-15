import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                // Branding
                VStack(spacing: 8) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 64))
                        .foregroundStyle(.tint)
                    Text("PaperBrain")
                        .font(.largeTitle.bold())
                    Text("Your handwritten notes, made searchable")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                // Form
                VStack(spacing: 16) {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                        .textFieldStyle(.roundedBorder)

                    SecureField("Password", text: $password)
                        .textContentType(isSignUp ? .newPassword : .password)
                        .textFieldStyle(.roundedBorder)

                    if let error = authVM.error {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }

                    Button {
                        Task {
                            if isSignUp {
                                await authVM.signUp(email: email, password: password)
                            } else {
                                await authVM.signIn(email: email, password: password)
                            }
                        }
                    } label: {
                        Text(isSignUp ? "Create Account" : "Sign In")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(email.isEmpty || password.count < 6)
                }
                .padding(.horizontal, 32)

                Button {
                    isSignUp.toggle()
                    authVM.error = nil
                } label: {
                    Text(isSignUp ? "Already have an account? Sign in" : "Don't have an account? Sign up")
                        .font(.footnote)
                }

                Spacer()
            }
            .navigationTitle("")
            .navigationBarHidden(true)
        }
    }
}
