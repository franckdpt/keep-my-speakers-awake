import SwiftUI
import KMSACore

/// One stable footer slot for search, update, progress and completion.
struct UpdateControl: View {
    @ObservedObject var updater: UpdateModel
    let action: () -> Void

    var body: some View {
        VStack(spacing: 5) {
            Group {
                if updater.showsProgress {
                    VStack(spacing: 3) {
                        HStack {
                            Text(L10n.text(updater.status ?? .checkingUpdates))
                            Spacer(minLength: 8)
                            if let fraction = updater.downloadProgress {
                                Text("\(Int((fraction * 100).rounded())) %")
                                    .monospacedDigit()
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        if let fraction = updater.downloadProgress {
                            ProgressView(value: fraction, total: 1)
                                .controlSize(.small)
                                .accessibilityLabel(L10n.text(.downloadingUpdate))
                        } else {
                            ProgressView().progressViewStyle(.linear)
                                .controlSize(.small)
                                .accessibilityLabel(L10n.text(updater.status ?? .checkingUpdates))
                        }
                    }
                } else if updater.isUpToDate {
                    HStack(spacing: 8) {
                        Label(L10n.text(.appUpToDate), systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize()
                        Spacer(minLength: 0)
                        Button(L10n.text(.checkUpdates), action: action)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(updater.busy)
                            .help(L10n.text(.automaticUpdateChecks))
                    }
                } else {
                    Button(action: action) {
                        Text(updater.buttonTitle)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(updater.busy)
                    .help(L10n.text(updater.hasUpdate ? .updateExplanation : .automaticUpdateChecks))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            if let error = updater.errorMessage, !updater.showsProgress {
                Text(L10n.text(error))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
