//
//  PrepareBackupView.swift
//  MobileTransfer
//
//  Created by 秋星桥 on 2024/9/25.
//

import AppleMobileDeviceLibrary
import SwiftUI
import UniformTypeIdentifiers

struct PrepareBackupView: View {
    @Environment(ViewModel.self) var vm
    @State private var encryptionInProgress = false
    @State private var choosingLocation = false
    @State private var source: Archives.BackupSource?
    @State private var choseNewLocation = false
    @State private var batteryInformation: [DeviceInfoField] = []
    @State private var storageInformation: [DeviceInfoField] = []
    @State private var applicationInformation: [DeviceInfoField] = []
    @State private var isReadingInformation = false
    @State private var didReadInformation = false
    @State private var showAllInformation = false

    private var deviceInformation: [DeviceInfoField] {
        DeviceInfoField.rows(from: vm.selectedDeviceRecord?.dictionary)
    }

    private var canStartBackup: Bool {
        !encryptionInProgress && !choosingLocation && (source != nil || choseNewLocation)
    }

    var body: some View {
        VStack(spacing: 16) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    Text("Device Details")
                        .font(.title2)
                        .bold()

                    deviceHeader
                    backupLocationSelection
                    BackupEncryptionIndicatorView(isEnabling: $encryptionInProgress)

                    if vm.showAppPackageDownloadPanel {
                        BackupApplicationView()
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }
                    allDeviceInformation
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
            .disabled(!canStartBackup)
        }
        .animation(.spring, value: vm.showAppPackageDownloadPanel)
        .frame(maxWidth: 650, maxHeight: .infinity)
        .padding(.horizontal, 32)
        .padding(.bottom, 16)
        .onAppear { readAdditionalInformation() }
    }

    private var deviceHeader: some View {
        CardContentView {
            VStack(spacing: 8) {
                Image(systemName: vm.selectedDeviceIcon)
                    .font(.system(size: 76, weight: .ultraLight))
                    .frame(width: 112, height: 112)
                    .itmGlassSurface(cornerRadius: 28)
                    .accessibilityHidden(true)
                Text(vm.selectedDeviceName ?? String(localized: "Unnamed Device"))
                    .font(.title2.bold())
                Text(vm.selectedDeviceModel ?? String(localized: "Unknown Model"))
                    .foregroundStyle(.secondary)
                if let version = vm.selectedDeviceVersion {
                    HStack(spacing: 4) {
                        Text("System Version")
                        Text(version)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                if let serial = vm.selectedDeviceRecord?.serialNumber {
                    HStack(spacing: 4) {
                        Text("Serial Number")
                        Text(serial).textSelection(.enabled)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                HStack(spacing: 20) {
                    if let charge = batteryInformation.first(where: { $0.key == "BatteryCurrentCapacity" }) {
                        Label {
                            HStack(spacing: 4) {
                                Text("Battery")
                                Text("\(charge.value)%")
                            }
                        } icon: {
                            Image(systemName: "battery.100percent")
                        }
                    }
                    if let available = storageInformation.first(where: { $0.key == "AmountDataAvailable" }),
                       let bytes = Int64(available.value)
                    {
                        Label {
                            HStack(spacing: 4) {
                                Text("Available Storage")
                                Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                            }
                        } icon: {
                            Image(systemName: "internaldrive")
                        }
                    }
                    if !applicationInformation.isEmpty {
                        Label {
                            HStack(spacing: 4) {
                                Text("Installed Apps")
                                Text("\(applicationInformation.count)")
                            }
                        } icon: {
                            Image(systemName: "square.grid.2x2")
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var backupLocationSelection: some View {
        CardContentView {
            CardContentHeader(icon: "folder", title: "Storage Location") {}
            if let source {
                Text(source.url.path)
                    .textSelection(.enabled)
                switch source.mode {
                case .incremental:
                    Text("A new incremental version will be created. The selected backup stays unchanged.")
                case .resumeIncremental:
                    Text("The unfinished incremental version will continue from its previous complete snapshot.")
                case .retryFull:
                    Text("This backup has no verified incremental checkpoint. Retrying may transfer all device data again.")
                }
            } else if choseNewLocation {
                Text(vm.backupLocation)
                    .textSelection(.enabled)
            } else {
                Text("Choose a backup location before starting.")
            }
            Menu {
                Button("New Backup…") { chooseNewLocation() }
                Button("Continue or Update an Existing Backup…") { chooseExistingBackup() }
            } label: {
                if source == nil && !choseNewLocation {
                    Label("Choose Backup Location", systemImage: "folder")
                } else {
                    Label("Change Backup Location", systemImage: "folder")
                }
            }
            .disabled(choosingLocation)
        }
        .font(.subheadline)
    }

    private var allDeviceInformation: some View {
        CardContentView {
            DisclosureGroup(isExpanded: $showAllInformation) {
                VStack(alignment: .leading, spacing: 16) {
                    informationSection("Device", fields: deviceInformation)
                    informationSection("Battery", fields: batteryInformation)
                    informationSection("Storage", fields: storageInformation)
                    informationSection("Installed Apps", fields: applicationInformation)
                }
                .padding(.top, 12)
            } label: {
                HStack {
                    Label("All Device Information", systemImage: "list.bullet.rectangle")
                    Spacer()
                    Text("\(deviceInformation.count + batteryInformation.count + storageInformation.count + applicationInformation.count)")
                        .foregroundStyle(.secondary)
                }
            }
            if isReadingInformation {
                ProgressView("Reading device information…")
                    .controlSize(.small)
            }
            Text("Photo count is not available from device information.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func informationSection(_ title: LocalizedStringKey, fields: [DeviceInfoField]) -> some View {
        if !fields.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                ForEach(fields) { field in
                    HStack(alignment: .top, spacing: 12) {
                        Text(field.key)
                            .foregroundStyle(.secondary)
                            .frame(width: 180, alignment: .leading)
                        Text(field.value)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.caption)
                    Divider()
                }
            }
        }
    }

    private func readAdditionalInformation() {
        guard !didReadInformation, let udid = vm.deviceIdentifier else { return }
        didReadInformation = true
        isReadingInformation = true
        DispatchQueue.global(qos: .utility).async {
            let manager = AppleMobileDeviceManager.shared
            let battery = DeviceInfoField.rows(from: manager.readFromLockdown(
                udid: udid, domain: "com.apple.mobile.battery", connection: .usb
            )?.value)
            let storage = DeviceInfoField.rows(from: manager.readFromLockdown(
                udid: udid, domain: "com.apple.disk_usage", connection: .usb
            )?.value)
            DispatchQueue.main.async {
                guard vm.deviceIdentifier == udid else { return }
                batteryInformation = battery
                storageInformation = storage
            }

            let apps = manager.listApplications(udid: udid, connection: .usb, includeIcons: false)
            let appFields = apps?.map { identifier, data -> DeviceInfoField in
                let values = data.value as? [String: AnyCodable]
                let name = values?["CFBundleDisplayName"]?.value as? String ?? identifier
                let version = values?["CFBundleShortVersionString"]?.value as? String
                return DeviceInfoField(key: identifier, value: version.map { "\(name) · \($0)" } ?? name)
            }.sorted { $0.key < $1.key } ?? []
            DispatchQueue.main.async {
                guard vm.deviceIdentifier == udid else { return }
                applicationInformation = appFields
                isReadingInformation = false
            }
        }
    }

    private func chooseNewLocation() {
        choosingLocation = true
        vm.pickSaveLocation { chosen in
            choosingLocation = false
            if chosen {
                source = nil
                choseNewLocation = true
            }
        }
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
                    case let .success(value):
                        source = value
                        choseNewLocation = false
                    case let .failure(error): NSAlert(error: error).beginSheetModal(for: window)
                    }
                }
            }
        }
    }

    private func startBackup() {
        guard let source else {
            guard choseNewLocation else { return }
            vm.page = .backupProgress
            return
        }

        choosingLocation = true
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

private struct DeviceInfoField: Identifiable {
    let key: String
    let value: String

    var id: String { key }

    static func rows(from raw: Any?) -> [DeviceInfoField] {
        if let wrapped = raw as? AnyCodable { return rows(from: wrapped.value) }
        guard let dictionary = raw as? [String: Any] else { return [] }
        return dictionary.keys.sorted().compactMap { key in
            guard let value = dictionary[key] else { return nil }
            return DeviceInfoField(key: key, value: format(value))
        }
    }

    private static func format(_ value: Any) -> String {
        if let wrapped = value as? AnyCodable { return format(wrapped.value) }
        if let data = value as? Data {
            return data.map { String(format: "%02X", $0) }.joined()
        }
        if let date = value as? Date {
            return date.formatted(date: .numeric, time: .standard)
        }
        if let dictionary = value as? [String: Any] {
            return dictionary.keys.sorted().compactMap { key in
                dictionary[key].map { "\(key): \(format($0))" }
            }.joined(separator: "\n")
        }
        if let array = value as? [Any] {
            return array.map { format($0) }.joined(separator: ", ")
        }
        return String(describing: value)
    }
}
