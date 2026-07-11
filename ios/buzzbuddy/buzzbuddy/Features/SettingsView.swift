//
//  SettingsView.swift
//  buzzbuddy
//
//  Created by Max DeWeese on 7/10/26.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
                    .padding(.bottom, 14)

                ScrollView {
                    content
                        .padding(.horizontal, 12)
                        .padding(.top, 16)
                        .padding(.bottom, 24)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionGroup(title: "Safety") {
                toggleRow(
                    icon: "phone.fill",
                    title: "Automatically Call Emergency Contact",
                    isOn: $settings.enableAutoCallContact
                )
                toggleRow(
                    icon: "speaker.wave.2.fill",
                    title: "Sound Effects",
                    isOn: $settings.soundEffects
                )
            }

            sectionGroup(title: "Biometrics") {
                stepperRow(
                    icon: "scalemass.fill",
                    title: "Weight",
                    value: settings.weight,
                    unit: "kg"
                ) {
                    settings.weight -= 1
                } onIncrement: {
                    settings.weight += 1
                }
                stepperRow(
                    icon: "ruler.fill",
                    title: "Height",
                    value: settings.height,
                    unit: "cm"
                ) {
                    settings.height -= 1
                } onIncrement: {
                    settings.height += 1
                }
            }
        }
    }

    // MARK: - Section Group

    private func sectionGroup<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption)
                .fontWeight(.semibold)
                .tracking(0.8)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            VStack(spacing: 10) {
                content()
            }
        }
    }

    // MARK: - Toggle Row

    private func toggleRow(icon: String, title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            Text(title)
                .font(.system(size: 15))
                .foregroundStyle(.primary)

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
    }

    // MARK: - Stepper Row

    private func stepperRow(
        icon: String,
        title: String,
        value: Int,
        unit: String,
        onDecrement: @escaping () -> Void,
        onIncrement: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            Text(title)
                .font(.system(size: 15))
                .foregroundStyle(.primary)

            Spacer()

            Text("\(value) \(unit)")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 0) {
                Button(action: onDecrement) {
                    Image(systemName: "minus")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)

                Divider()
                    .frame(height: 16)

                Button(action: onIncrement) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.tertiarySystemFill))
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppSettings())
}
