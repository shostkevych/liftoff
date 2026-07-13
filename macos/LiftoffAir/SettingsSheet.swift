import SwiftUI
import UIKit

/// App settings: the Mac terminal's IP address and a Face ID lock toggle.
struct SettingsSheet: View {
    @Binding var host: String
    @Binding var faceIDEnabled: Bool
    /// Called with the (trimmed) host when the user commits a change.
    let onApply: (String) -> Void
    /// Unpair this phone: forget the Mac and return to the pairing screen.
    let onDisconnect: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draftHost: String
    @State private var confirmingDisconnect = false

    init(host: Binding<String>, faceIDEnabled: Binding<Bool>,
         onApply: @escaping (String) -> Void, onDisconnect: @escaping () -> Void) {
        _host = host
        _faceIDEnabled = faceIDEnabled
        self.onApply = onApply
        self.onDisconnect = onDisconnect
        _draftHost = State(initialValue: host.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Image(systemName: "desktopcomputer")
                            .foregroundStyle(.secondary)
                            .frame(width: 22)
                        TextField("192.168.0.10", text: $draftHost)
                            .keyboardType(.numbersAndPunctuation)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .onSubmit(apply)
                    }
                } header: {
                    Text("Main Terminal IP")
                } footer: {
                    Text("The Mac running Liftoff on your local network.")
                }

                Section {
                    Toggle(isOn: $faceIDEnabled) {
                        Label("Require Face ID", systemImage: "faceid")
                    }
                    .tint(.brand)
                } footer: {
                    Text("Lock the app behind Face ID when it opens.")
                }

                Section {
                    Button(role: .destructive) {
                        confirmingDisconnect = true
                    } label: {
                        Label("Disconnect Phone", systemImage: "iphone.slash")
                    }
                } footer: {
                    Text("Forget this Mac and return to the pairing screen, so you can scan a new code.")
                }
            }
            .scrollContentBackground(.hidden)
            .background {
                LinearGradient(colors: [Color(white: 0.10), Color.black],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { apply(); dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .confirmationDialog("Disconnect this phone?", isPresented: $confirmingDisconnect, titleVisibility: .visible) {
                Button("Disconnect", role: .destructive) {
                    dismiss()
                    onDisconnect()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll need to scan the pairing code on your Mac again to reconnect.")
            }
        }
        .tint(.brand)
        .preferredColorScheme(.dark)
    }

    private func apply() {
        let trimmed = draftHost.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        host = trimmed
        onApply(trimmed)
    }
}
