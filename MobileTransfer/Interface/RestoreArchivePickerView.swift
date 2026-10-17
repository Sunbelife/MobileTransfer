//
//  RestoreArchivePickerView.swift
//  MobileTransfer
//
//  Created by 秋星桥 on 2024/9/26.
//

import SwiftUI

struct RestoreArchivePickerView: View {
    @Environment(ViewModel.self) private var vm
    @State private var backups: [Archives.BackupRecord] = []
    @State private var loading = true
    @State private var checkingPath: String?

    var body: some View {
        CardContentView {
            CardContentHeader(icon: "archivebox", title: "Backup History") {
                if vm.restoreLocation != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            if let selected = vm.restoreLocation {
                Text("Selected backup")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(URL(fileURLWithPath: selected).lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if loading {
                ProgressView("Finding backups…")
            } else if backups.isEmpty {
                Text("No completed backup found for this device.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(backups.indices, id: \.self) { index in
                        let backup = backups[index]
                        Button {
                            select(backup)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "clock.arrow.circlepath")
                                VStack(alignment: .leading, spacing: 3) {
                                    if index == 0 {
                                        Text("Latest backup")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(backup.date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.headline)
                                    Text(backup.url.lastPathComponent)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer()
                                if checkingPath == backup.id {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(checkingPath != nil)
                        if index < backups.count - 1 { Divider() }
                    }
                }
            }

            Divider()
            HStack {
                Button("Choose Backup from File…") { vm.pickRestoreArchive() }
                Button("Show In Finder") { vm.showRestoreBackupLocationInFinder() }
                    .disabled(vm.restoreLocation == nil)
                Spacer()
            }
        }
        .onAppear(perform: loadHistory)
        .onChange(of: vm.restoreLocation) { _, _ in loadHistory() }
    }

    private func loadHistory() {
        guard let deviceIdentifier = vm.deviceIdentifier else { return }
        loading = true
        DispatchQueue.global(qos: .utility).async {
            let result = Archives.availableBackups(for: deviceIdentifier)
            DispatchQueue.main.async {
                backups = result
                loading = false
            }
        }
    }

    private func select(_ backup: Archives.BackupRecord) {
        checkingPath = backup.id
        DispatchQueue.global(qos: .userInitiated).async {
            let info = Archives.validateRestoreArchive(at: backup.url)
            DispatchQueue.main.async {
                checkingPath = nil
                guard info.verified else {
                    Archives.presentArchiveBroken(info: info)
                    return
                }
                vm.restoreLocation = backup.url.path
                vm.restoreArchiveIsPasswordProtected = info.isEncrypted
                vm.restoreApplicationsCount = info.applications
                vm.restoreArchiveSystemBuildVersion = info.systemBuildVersion
                Archives.rememberCompletedBackup(at: backup.url)
            }
        }
    }
}
