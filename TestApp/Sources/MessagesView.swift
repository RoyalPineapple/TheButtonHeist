import SwiftUI

struct MessagesView: View {
    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""

    private static let botReplies = [
        "That's a great point!",
        "Hmm, let me think about that...",
        "I couldn't agree more.",
        "Interesting — tell me more?",
        "Ha! You always know what to say.",
        "Noted. I'll get back to you on that.",
        "Wait, really? That's wild.",
        "Okay but have you considered the alternative?",
        "You're on fire today.",
        "I was literally just thinking the same thing."
    ]

    var body: some View {
        VStack(spacing: 0) {
            if messages.isEmpty {
                ContentUnavailableView(
                    "No messages yet",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Start a conversation")
                )
                .frame(maxHeight: .infinity)
            } else {
                messageList
            }
            inputBar
        }
        .navigationTitle("Messages")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation {
                        messages.removeAll()
                    }
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(messages.isEmpty)
            }
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(messages) { message in
                        MessageBubble(
                            text: message.text,
                            sender: message.sender,
                            timestamp: message.timestamp
                        )
                        .id(message.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: messages.count) {
                if let last = messages.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Message...", text: $inputText)
                .textFieldStyle(.roundedBorder)

            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let userMessage = ChatMessage(text: trimmed, sender: .you, timestamp: Date())
        withAnimation {
            messages.append(userMessage)
        }
        inputText = ""

        scheduleBotReply()
    }

    private func scheduleBotReply() {
        Task {
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }
            let reply = Self.botReplies.randomElement() ?? "..."
            let botMessage = ChatMessage(text: reply, sender: .bot, timestamp: Date())
            withAnimation {
                messages.append(botMessage)
            }
        }
    }
}

// MARK: - Subviews

private struct MessageBubble: View {
    let text: String
    let sender: ChatMessage.Sender
    let timestamp: Date

    var body: some View {
        HStack {
            if sender == .you { Spacer(minLength: 60) }

            VStack(alignment: sender == .you ? .trailing : .leading, spacing: 2) {
                Text(text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(sender == .you ? Color.blue : Color(.systemGray5))
                    .foregroundStyle(sender == .you ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                Text(timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if sender == .bot { Spacer(minLength: 60) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityCustomContent(Text("Time"), Text(timestamp, style: .time))
    }

    private var accessibilityDescription: String {
        let senderName = sender == .you ? "You" : "Bot"
        return "\(senderName) said: \(text)"
    }
}

// MARK: - Model

private struct ChatMessage: Identifiable {
    let id = UUID()
    let text: String
    let sender: Sender
    let timestamp: Date

    enum Sender: String, Sendable {
        case you
        case bot
    }
}

#Preview {
    NavigationStack {
        MessagesView()
    }
    .environment(AppSettings())
}
