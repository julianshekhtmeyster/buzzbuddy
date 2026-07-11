import SwiftUI

/// Preview of what a designated driver could ask after receiving the
/// notify_contact alert. Backed by a separate DO agent (not the examiner
/// loop) with its own knowledge base -- read-only Q&A grounded in this
/// session's already-computed data. Never makes an impairment decision
/// itself. There's no real DD-delivery mechanism yet (no SMS deep link);
/// this view is reachable only from within the drinker's own app, for
/// demo/testing purposes.
struct DDCompanionPreviewView: View {
    let sessionId: String
    var api: BuzzBuddyAPIProtocol = BuzzBuddyAPI()

    private struct ChatMessage: Identifiable {
        enum Role { case dd, agent }
        let id = UUID()
        let role: Role
        let text: String
    }

    @State private var messages: [ChatMessage] = []
    @State private var input = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("Preview: what your designated driver could ask after receiving the alert.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(messages) { message in
                                messageBubble(message).id(message.id)
                            }
                            if isSending {
                                ProgressView()
                                    .padding(.leading, 8)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: messages.count) {
                        if let last = messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                HStack {
                    TextField("Ask a question...", text: $input)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { send() }
                    Button("Send") { send() }
                        .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                }
                .padding()
            }
            .navigationTitle("DD Companion")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private func messageBubble(_ message: ChatMessage) -> some View {
        HStack {
            if message.role == .agent {
                bubble(for: message)
                Spacer(minLength: 40)
            } else {
                Spacer(minLength: 40)
                bubble(for: message)
            }
        }
    }

    private func bubble(for message: ChatMessage) -> some View {
        Text(message.text)
            .padding(10)
            .background(
                (message.role == .dd ? Color.blue : Color.gray).opacity(0.15),
                in: RoundedRectangle(cornerRadius: 12)
            )
    }

    private func send() {
        let question = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isSending else { return }
        messages.append(ChatMessage(role: .dd, text: question))
        input = ""
        errorMessage = nil
        isSending = true
        Task {
            defer { isSending = false }
            do {
                let response = try await api.sendDDChatMessage(sessionId: sessionId, question: question)
                messages.append(ChatMessage(role: .agent, text: response.answer))
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    DDCompanionPreviewView(sessionId: "preview-session")
}
