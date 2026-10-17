//
//  BackupDeviceDataTaskView.swift
//  BBackupp
//
//  Created by 秋星桥 on 2024/3/15.
//

import SwiftUI

struct BackupDeviceDataTaskView: View {
    let task: MobileBackupTask

    @State private var showingDetails = false

    private var hasOverallProgress: Bool {
        task.overall.completedUnitCount > 0
    }

    private var overallPercent: String {
        "\(Int(task.overall.fractionCompleted * 100))%"
    }

    private var currentTransfer: String? {
        guard task.hasStartedTransfer,
              task.current.totalUnitCount > 0
        else { return nil }

        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let received = formatter.string(fromByteCount: task.current.completedUnitCount)
        let total = formatter.string(fromByteCount: task.current.totalUnitCount)
        return "\(received) / \(total)"
    }

    var body: some View {
        CardContentView {
            HStack(spacing: 10) {
                Image(systemName: "arrow.right.doc.on.clipboard")
                    .accessibilityHidden(true)
                Text("Backup")
                    .bold()
                Spacer()
                if task.completed {
                    Image(systemName: task.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(task.success ? .green : .red)
                        .accessibilityHidden(true)
                } else if hasOverallProgress {
                    Text(overallPercent)
                        .monospacedDigit()
                }
                Button {
                    showingDetails = true
                } label: {
                    Image(systemName: "exclamationmark.circle")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .help("View backup details")
                .accessibilityLabel("View backup details")
                .popover(isPresented: $showingDetails, arrowEdge: .trailing) {
                    details
                }
            }

            VStack(alignment: .leading, spacing: 18) {
                status
                    .font(.title2.weight(.semibold))

                Group {
                    if task.completed || hasOverallProgress {
                        ProgressView(
                            value: Double(task.overall.completedUnitCount),
                            total: Double(max(task.overall.totalUnitCount, 1))
                        )
                    } else {
                        ProgressView()
                    }
                }
                .progressViewStyle(.linear)
                .controlSize(.large)
                .tint(.accentColor)
                .scaleEffect(x: 1, y: 2.5)
                .frame(height: 18)

                supportingText
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 24)
        }
        .frame(maxWidth: 760)
    }

    @ViewBuilder
    private var status: some View {
        if task.completed {
            if task.success {
                Text("Backup complete")
            } else {
                Text("Backup failed")
                    .foregroundStyle(.red)
            }
        } else if task.hasStartedTransfer {
            Text("Transferring device data…")
        } else {
            Text("Preparing data on iPhone…")
        }
    }

    @ViewBuilder
    private var supportingText: some View {
        if task.completed {
            if task.success {
                Text("Device data has been received.")
            } else {
                Text("Open details to see what happened.")
            }
        } else if let currentTransfer {
            HStack(spacing: 6) {
                Text("Current batch")
                Text(currentTransfer)
                    .monospacedDigit()
            }
        } else {
            Text("The first backup may take a few minutes to prepare. Confirm any prompt on your iPhone.")
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Backup details")
                .font(.headline)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(task.output.reversed()) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            Text(entry.date.formatted(date: .omitted, time: .shortened))
                                .foregroundStyle(.secondary)
                            Text(entry.text)
                                .foregroundStyle(entry.color)
                                .textSelection(.enabled)
                        }
                        .font(.footnote.monospaced())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(width: 620, height: 420)
    }
}

private extension MobileBackupTask.Log {
    var color: Color {
        if text.lowercased().contains("error") {
            return .red
        }
        if text.lowercased().contains("warning") {
            return .orange
        }
        return .primary
    }
}
