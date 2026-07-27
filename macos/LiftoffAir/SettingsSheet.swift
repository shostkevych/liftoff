import SwiftUI

/// App settings: transport choice, privacy lock, and pairing management.
struct SettingsSheet: View {
    @Binding var faceIDEnabled: Bool
    @Binding var connectionMode: CompanionClient.ConnectionMode
    /// Unpair this phone: forget the Mac and return to the pairing screen.
    let onDisconnect: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDisconnect = false

    init(faceIDEnabled: Binding<Bool>,
         connectionMode: Binding<CompanionClient.ConnectionMode>,
         onDisconnect: @escaping () -> Void) {
        _faceIDEnabled = faceIDEnabled
        _connectionMode = connectionMode
        self.onDisconnect = onDisconnect
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Connection", selection: $connectionMode) {
                        ForEach(CompanionClient.ConnectionMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(connectionMode == .relay
                         ? "Connect securely through Liftoff Relay."
                         : "Connect only through saved addresses on your local network.")
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
                    Button("Done") { dismiss() }
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

}
