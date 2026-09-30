import SwiftUI

struct AIAssistantSettingsPane: View {
    @State private var settings = AIAssistantSettings.shared
    @State private var provider: AIProvider = .openAI
    @State private var key = ""
    @State private var model = ""
    @State private var savedKey = ""
    @State private var savedModel = ""
    @State private var models: [AIClient.Model] = []
    @State private var loading = false
    @State private var message: String?
    @State private var isError = false
    @State private var loadTask: Task<Void, Never>?
    @State private var generation = UUID()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("AI Assistant").font(.system(size: 24, weight: .semibold))
                    Text("Choose the provider and model for terminal summaries and welcome greetings.")
                        .foregroundStyle(.secondary)
                }
                if !settings.model(for: settings.provider).isEmpty {
                    Label("Active: \(settings.provider.title) · \(settings.model(for: settings.provider))", systemImage: "checkmark.circle")
                        .font(.callout).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Provider", selection: $provider) {
                        ForEach(AIProvider.allCases) { Text($0.title).tag($0) }
                    }
                    .onChange(of: provider) { _, _ in loadSavedProvider() }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("API key").fontWeight(.medium)
                            Spacer()
                            Link("Get an API key ↗", destination: provider.keyURL)
                        }
                        SecureField("Enter your \(provider.title) API key", text: $key)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: key) { _, _ in
                                cancelLoad()
                                models = []
                                message = nil
                            }
                        Text("Keys are stored in your Mac’s Keychain, separately for each provider.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        Button(loading ? "Loading Models…" : "Load Models", action: fetchModels)
                            .disabled(loading || key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if loading { ProgressView().controlSize(.small) }
                    }
                    Picker("Model", selection: $model) {
                        Text("Choose a model").tag("")
                        if !model.isEmpty && !models.contains(where: { $0.id == model }) {
                            Text(model + " (saved)").tag(model)
                        }
                        ForEach(models) { item in
                            Text(item.name == item.id ? item.id : "\(item.name) · \(item.id)").tag(item.id)
                        }
                    }
                    .disabled(models.isEmpty || loading)
                    Text("Enter your key, load the available models, then choose one and save.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(20)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                HStack {
                    Button("Remove Saved Key", role: .destructive) { removeKey() }
                    Spacer()
                    Button("Save") { save() }
                        .buttonStyle(.borderedProminent)
                        .disabled(loading || key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isEmpty || !canSave)
                }
                if let message {
                    Label(message, systemImage: isError ? "exclamationmark.circle" : "checkmark.circle")
                        .foregroundStyle(isError ? Color.orange : Color.green)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Only selected terminal text is sent when you request a summary. Greetings use a short prompt without terminal content. AI features stay off until a provider, key, and model are saved.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(28)
        }
        .onAppear { provider = settings.provider; loadSavedProvider() }
        .onDisappear { cancelLoad() }
    }

    private var canSave: Bool {
        models.contains { $0.id == model } ||
            (model == savedModel && key == savedKey)
    }
    private func cancelLoad() {
        loadTask?.cancel()
        loadTask = nil
        generation = UUID()
        loading = false
    }
    private func loadSavedProvider() {
        cancelLoad()
        savedKey = settings.key(for: provider)
        savedModel = settings.model(for: provider)
        key = savedKey
        model = savedModel
        models = []
        message = nil
    }
    private func fetchModels() {
        cancelLoad()
        let token = generation
        let selectedProvider = provider
        let enteredKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        loading = true
        message = nil
        loadTask = Task { @MainActor in
            do {
                let available = try await AIClient.listModels(provider: selectedProvider, key: enteredKey)
                guard !Task.isCancelled, generation == token else { return }
                models = available
                if !available.contains(where: { $0.id == model }) { model = "" }
                loading = false
                message = "Models loaded. Choose a model and save."
                isError = false
            } catch {
                guard !Task.isCancelled, generation == token else { return }
                loading = false
                message = error.localizedDescription
                isError = true
            }
        }
    }
    private func save() {
        do {
            try settings.save(provider: provider, model: model, key: key.trimmingCharacters(in: .whitespacesAndNewlines))
            savedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            savedModel = model
            message = "Saved. AI Assistant uses \(provider.title) · \(model)."
            isError = false
        } catch {
            message = error.localizedDescription
            isError = true
        }
    }
    private func removeKey() {
        cancelLoad()
        do {
            try settings.removeKey(for: provider)
            savedKey = ""
            savedModel = ""
            key = ""
            model = ""
            models = []
            message = "API key removed."
            isError = false
        } catch {
            message = error.localizedDescription
            isError = true
        }
    }
}
