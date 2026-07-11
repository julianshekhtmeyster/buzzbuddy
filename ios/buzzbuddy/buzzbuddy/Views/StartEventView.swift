import SwiftUI

struct StartEventView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var eventStore = EventStore.shared
    @State private var selectedEvent: Event?

    /// The backend rejects event creation with no baseline on file (there's
    /// nothing to detect deviation from) -- check client-side first so the
    /// user gets a helpful nudge instead of a raw error string.
    private var hasBaseline: Bool {
        appState.reactionBaselineMs != nil
            && appState.gyroBaselineScore != nil
            && appState.memoryBaselinePercent != nil
    }

    private var canGo: Bool {
        !appState.isLoading && selectedEvent != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            if hasBaseline {
                if eventStore.events.isEmpty {
                    noEventsState
                } else {
                    checkInState
                }
            } else {
                noBaselineState
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 28)
    }

    // MARK: - States

    private var checkInState: some View {
        VStack(spacing: 20) {
            badge(systemImage: "mappin.and.ellipse")

            Text("What event are you at right now?")
                .font(.system(size: 22, weight: .bold))
                .multilineTextAlignment(.center)

            eventPicker

            goButton

            if let error = appState.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var noEventsState: some View {
        VStack(spacing: 16) {
            badge(systemImage: "mappin.and.ellipse")

            Text("Add an event on the Events tab first.")
                .font(.system(size: 17, weight: .semibold))
                .multilineTextAlignment(.center)

            capsuleButton("Go to the Events tab") { dismiss() }
        }
        .frame(maxWidth: .infinity)
    }

    private var noBaselineState: some View {
        VStack(spacing: 16) {
            badge(systemImage: "waveform.path.ecg")

            Text("Set your sober baseline before starting a check-in.")
                .font(.system(size: 20, weight: .bold))
                .multilineTextAlignment(.center)

            Text("The examiner compares your test results against your own baseline -- without one, it has nothing to compare to.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Baseline setup lives on the Baseline tab underneath this
            // full-screen check-in flow, not as a nested page here --
            // pushing a second BaselineView instance inside this modal
            // just duplicates that one true page and confuses navigation.
            capsuleButton("Go to the Baseline tab") { dismiss() }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Pieces

    private func badge(systemImage: String) -> some View {
        Circle()
            .fill(Color.yellow)
            .frame(width: 64, height: 64)
            .overlay(
                Image(systemName: systemImage)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }

    private var eventPicker: some View {
        Picker(selection: $selectedEvent) {
            Text("Select an event").tag(Event?.none)
            ForEach(eventStore.events) { event in
                Text(event.name).tag(Optional(event))
            }
        } label: {
            HStack(spacing: 10) {
                Text(selectedEvent?.name ?? "Select an event")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(selectedEvent == nil ? Color.secondary : Color.primary)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
        }
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity)
    }

    private var goButton: some View {
        Button {
            guard let selectedEvent else { return }
            Task { await appState.startEvent(name: selectedEvent.name) }
        } label: {
            Text(appState.isLoading ? "Starting..." : "Go")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(canGo ? .white : Color.gray)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    Capsule().fill(canGo ? Color.yellow : Color.yellow.opacity(0.35))
                )
        }
        .disabled(!canGo)
    }

    private func capsuleButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Capsule().fill(Color.yellow))
        }
    }
}

#Preview {
    StartEventView().environmentObject(AppState())
}
