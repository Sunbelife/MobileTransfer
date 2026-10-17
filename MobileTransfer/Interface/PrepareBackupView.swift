//
//  PrepareBackupView.swift
//  MobileTransfer
//
//  Created by 秋星桥 on 2024/9/25.
//

import SwiftUI

struct PrepareBackupView: View {
    @Environment(ViewModel.self) var vm
    @State private var encryptionInProgress = false
    @State private var choosingLocation = false

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
                }
                .frame(maxWidth: .infinity)
            }

            Button {
                choosingLocation = true
                DispatchQueue.main.async {
                    vm.pickSaveLocation { chosen in
                        choosingLocation = false
                        if chosen { vm.page = .backupProgress }
                    }
                }
            } label: {
                CardContentView {
                    HStack(spacing: 8) {
                        if choosingLocation {
                            ProgressView()
                                .controlSize(.small)
                            Text("Opening Save Dialog…")
                        } else {
                            Text("Start Backup")
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
}
