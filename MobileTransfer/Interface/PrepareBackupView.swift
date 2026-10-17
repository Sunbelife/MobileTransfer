//
//  PrepareBackupView.swift
//  MobileTransfer
//
//  Created by 秋星桥 on 2024/9/25.
//

import SwiftUI
import UniformTypeIdentifiers

struct PrepareBackupView: View {
    @Environment(ViewModel.self) var vm
    @State private var encryptionInProgress = false
    @State private var choosingLocation = false
    @State private var source: Archives.BackupSource?

    var body: some View {
        VStack(spacing: 16) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    Text("Prepare Backup")
                        .font(.title2)
                        .bold()

                    CardContentView {
                        HStack(spacing: 16) {
                            Image(systemName: vm.selectedDeviceIcon)
                                .font(.system(size: 30))
                                .frame(width: 44)
                            VStack(alignment: .leading, spacing: 4) {
                                if let name = vm.selectedDeviceName {
                                    Text(name)
                                        .font(.headline)
                                } else {
                                    Text("Unnamed Device")
                                        .font(.headline)
                                }
                                if let model = vm.selectedDeviceModel {
                                    Text(model)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Unknown Model")
                                        .foregroundStyle(.secondary)
                                }
                                if let version = vm.selectedDeviceVersion {
                                    HStack(spacing: 4) {
                                        Text("System Version")
                                        Text(version)
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    }

                    if vm.showAppPackageDownloadPanel {
                        BackupApplicationView()
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }
                    BackupEncryptionIndicatorView(isEnabling: $encryptionInProgress)

                    CardContentView {
                        if let source {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(source.url.lastPathComponent)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                switch source.mode {
                                case .incremental:
                                    Text("A new incremental version will be created. The selected backup stays unchanged.")
                                case .resumeIncremental:
                                    Text("The unfinished incremental version will continue from its previous complete snapshot.")
                                case .retryFull:
                                    Text("This backup has no verified incremental checkpoint. Retrying may transfer all device data again.")
                                }
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            HStack {
                                Button("Choose Another Backup…") { chooseExistingBackup() }
                                Button("Start a New Backup") { self.source = nil }
                            }
                        } else {
                            Button("Continue or Update an Existing Backup…") { chooseExistingBackup() }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }

            Button {
                startBackup()
            } label: {
                CardContentView {
                    HStack(spacing: 8) {
                        if choosingLocation {
                            ProgressView()
                                .controlSize(.small)
                            Text("Preparing Backup…")
                        } else {
                            switch source?.mode {
                            case .incremental: Text("Start Incremental Backup")
                            case .resumeIncremental: Text("Resume Incremental Backup")
                            case .retryFull: Text("Retry Backup")
                            case nil: Text("Start Backup")
                            }
                        }
                    }
                    .foregroundStyle(.accent)
                    .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.plain)
            .disabled(encryptionInProgress || choosingLocation)
        }
        .animation(.spring, value: vm.showAppPackageDownloadPanel)
        .frame(maxWidth: 650, maxHeight: .infinity)
        .padding(.horizontal, 32)
        .padding(.bottom, 16)
    }

    private func chooseExistingBackup() {
        guard let window = NSApp.mainWindow ?? NSApp.windows.first,
              let archiveType = UTType("tech.nootag.itm.backup")
        else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [archiveType]
        panel.message = NSLocalizedString("Choose an Existing Backup", comment: "")
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url,
                  let identifier = vm.deviceIdentifier
            else { return }
            choosingLocation = true
            DispatchQueue.global(qos: .userInitiated).async {
                let result = Result {
                    try Archives.inspectBackupSource(at: url, deviceIdentifier: identifier)
                }
                DispatchQueue.main.async {
                    choosingLocation = false
                    switch result {
                    case let .success(value): source = value
                    case let .failure(error): NSAlert(error: error).beginSheetModal(for: window)
                    }
                }
            }
        }
    }

    private func startBackup() {
        choosingLocation = true
        guard let source else {
            vm.pickSaveLocation { chosen in
                choosingLocation = false
                if chosen { vm.page = .backupProgress }
            }
            return
        }

        let deviceName = vm.selectedDeviceName ?? "iPhone"
        let identifier = vm.deviceIdentifier ?? ""
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { () throws -> URL in
                let current = try Archives.inspectBackupSource(
                    at: source.url,
                    deviceIdentifier: identifier
                )
                switch (source.mode, current.mode) {
                case (.incremental, .incremental):
                    return try Archives.makeIncrementalVersion(from: source.url, deviceName: deviceName)
                case (.resumeIncremental, .resumeIncremental), (.retryFull, .retryFull):
                    return source.url
                default:
                    throw Archives.BackupSourceError.invalid
                }
            }
            DispatchQueue.main.async {
                choosingLocation = false
                switch result {
                case let .success(url):
                    vm.backupLocation = url.path
                    vm.page = .backupProgress
                case let .failure(error):
                    if let window = NSApp.mainWindow ?? NSApp.windows.first {
                        NSAlert(error: error).beginSheetModal(for: window)
                    }
                }
            }
        }
    }
}
