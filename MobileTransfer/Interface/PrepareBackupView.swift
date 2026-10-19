//
//  PrepareBackupView.swift
//  MobileTransfer
//
//  Created by 秋星桥 on 2024/9/25.
//

import AppleMobileDeviceLibrary
import Combine
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct PrepareBackupView: View {
    @Environment(ViewModel.self) var vm
    @Environment(\.scenePhase) private var scenePhase
    @State private var isReadingBattery = false
    private let batteryTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    var onBusyChange: (Bool) -> Void = { _ in }
    @State private var latestBackup: Archives.BackupRecord?
    @State private var loadingBackupHistory = true
    @State private var checkingRestoreBackup = false
    @State private var encryptionInProgress = false
    @State private var encryptionStatus: BackupEncryptionIndicatorView.Status = .finding
    @State private var choosingLocation = false
    @State private var source: Archives.BackupSource?
    @State private var choseNewLocation = false
    @State private var batteryInformation: [DeviceInfoField] = []
    @State private var storageInformation: [DeviceInfoField] = []
    @State private var applications: [InstalledApplication] = []
    @State private var iconReadProgress: Progress?
    @State private var isReadingApplications = false
    @State private var didReadApplications = false
    @State private var applicationReadFailed = false
    @State private var didReadInformation = false
    private enum Pane: String, CaseIterable, Identifiable {
        case general, applications, information
        var id: Self { self }
        var title: LocalizedStringKey {
            switch self {
            case .general: "General"
            case .applications: "Installed Apps"
            case .information: "Device Information"
            }
        }
    }
    @State private var pane: Pane = .general
    @State private var search = ""
    @State private var informationCategory = 0
    @State private var selectedInformation: String?

    private var deviceInformation: [DeviceInfoField] {
        DeviceInfoField.rows(from: vm.selectedDeviceRecord?.dictionary)
    }

    private var canStartBackup: Bool {
        !encryptionInProgress && !choosingLocation && !checkingRestoreBackup
            && (encryptionStatus == .enabled || encryptionStatus == .disabled)
            && (source != nil || choseNewLocation)
    }

    var body: some View {
        VStack(spacing: 0) {
            deviceHeader
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
            Divider()
            Picker("View", selection: $pane) {
                ForEach(Pane.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.vertical, 10)
            Divider()
            if pane == .general {
                generalView
            } else {
                informationTable
            }
            Divider()
            bottomBar
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear {
            readAdditionalInformation()
            loadLatestBackup()
        }
        .onDisappear {
            iconReadProgress?.cancel()
            onBusyChange(false)
        }
        .onChange(of: encryptionInProgress || choosingLocation || checkingRestoreBackup) {
            onBusyChange(encryptionInProgress || choosingLocation || checkingRestoreBackup)
        }
        .onReceive(batteryTimer) { _ in
            if scenePhase == .active { refreshBattery() }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active { refreshBattery() }
        }
        .onChange(of: pane) {
            search = ""
            if pane == .applications { readApplications() }
        }
    }

    private var deviceHeader: some View {
        HStack(spacing: 16) {
            Image(systemName: vm.selectedDeviceIcon)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(vm.selectedDeviceName ?? String(localized: "Unnamed Device"))
                    .font(.title2.bold())
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        deviceModel
                        capacityLabel
                        batteryLabel
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        deviceModel
                        HStack(spacing: 12) {
                            capacityLabel
                            batteryLabel
                        }
                    }
                }
                .foregroundStyle(.secondary)
                .font(.callout)
            }
            Spacer(minLength: 0)
        }
    }

    private var deviceModel: some View {
        Text(vm.selectedDeviceModel ?? String(localized: "Unknown Model"))
    }

    @ViewBuilder private var capacityLabel: some View {
        if let capacity = totalCapacity {
            Text(ByteCountFormatter.string(fromByteCount: capacity, countStyle: .file))
                .monospacedDigit()
        }
    }

    @ViewBuilder private var batteryLabel: some View {
        let status = DeviceBatteryStatus(values: Dictionary(uniqueKeysWithValues: batteryInformation.map { ($0.key, $0.value) }))
        if let percentage = status.percentage {
            HStack(spacing: 6) {
                Image(systemName: status.symbol)
                    .foregroundStyle(status.isCharging == true ? Color.green : percentage <= 20 ? Color.red : Color.secondary)
                    .shadow(color: .black.opacity(0.08), radius: 1, x: 0, y: 0.5)
                    .accessibilityHidden(true)
                Text("\(percentage)%").monospacedDigit()
            }
            .help(status.isCharging == true ? String(localized: "Charging") : status.isCharging == false ? String(localized: "Not Charging") : String(localized: "Unknown"))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Battery Level"))
            .accessibilityValue("\(percentage)%, \(status.isCharging == true ? String(localized: "Charging") : status.isCharging == false ? String(localized: "Not Charging") : String(localized: "Unknown"))")
        }
    }

    private var generalView: some View {
        GeometryReader { detail in
            ScrollView {
                VStack(spacing: 0) {
                    settingsRow("Software", compact: detail.size.width < 620) {
                        VStack(alignment: .leading, spacing: 10) {
                            if let version = vm.selectedDeviceVersion {
                                Text("iOS \(version)").fontWeight(.medium)
                            }
                            if let serial = vm.selectedDeviceRecord?.serialNumber {
                                HStack(spacing: 8) {
                                    Text("Serial Number").foregroundStyle(.secondary)
                                    Text(serial).monospaced().textSelection(.enabled)
                                }
                                .font(.callout)
                            }
                            Button {
                                pane = .information
                            } label: {
                                Text("Device Information")
                            }
                        }
                    }
                    Divider()
                    settingsRow("Backup", compact: detail.size.width < 620) {
                        VStack(alignment: .leading, spacing: 16) {
                            Label("Back up all device data to this Mac", systemImage: "desktopcomputer")
                                .fontWeight(.medium)
                            backupLocationSelection
                            BackupEncryptionIndicatorView(isEnabling: $encryptionInProgress, status: $encryptionStatus)
                            if vm.showAppPackageDownloadPanel {
                                BackupApplicationView()
                            }
                            ViewThatFits(in: .horizontal) {
                                HStack(alignment: .center, spacing: 20) {
                                    latestBackupDescription
                                    Spacer(minLength: 16)
                                    restoreBackupButton
                                }
                                VStack(alignment: .leading, spacing: 12) {
                                    latestBackupDescription
                                    restoreBackupButton
                                }
                            }
                        }
                    }
                    Divider()
                    settingsRow("Storage", compact: detail.size.width < 620) {
                        VStack(alignment: .leading, spacing: 12) {
                            if let available = availableCapacity {
                                LabeledContent("Available Storage") {
                                    Text(ByteCountFormatter.string(fromByteCount: available, countStyle: .file))
                                        .monospacedDigit()
                                }
                            } else {
                                Text("Storage information is unavailable.")
                                    .foregroundStyle(.secondary)
                            }
                            Button {
                                informationCategory = 2
                                pane = .information
                            } label: {
                                Text("Storage Information…")
                            }
                        }
                    }
                }
                .padding(.horizontal, detail.size.width < 620 ? 24 : 40)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private func settingsRow<Content: View>(_ title: LocalizedStringKey, compact: Bool, @ViewBuilder content: () -> Content) -> some View {
        Group {
            if compact {
                VStack(alignment: .leading, spacing: 12) {
                    Text(title).fontWeight(.semibold)
                    content()
                }
            } else {
                HStack(alignment: .top, spacing: 20) {
                    Text(title)
                        .fontWeight(.semibold)
                        .frame(width: 100, alignment: .trailing)
                    content()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 24)
    }

    private var latestBackupDescription: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Latest Completed Backup")
                .font(.callout)
                .foregroundStyle(.secondary)
            if loadingBackupHistory {
                Text("Finding backups…").foregroundStyle(.secondary)
            } else if let latestBackup {
                Text(latestBackup.date.formatted(date: .abbreviated, time: .shortened))
                Text(latestBackup.url.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("No Completed Backups")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var restoreBackupButton: some View {
        HStack(spacing: 8) {
            if checkingRestoreBackup { ProgressView().controlSize(.small) }
            Button("Restore Backup…", action: openRestore)
                .disabled(choosingLocation || encryptionInProgress || checkingRestoreBackup)
        }
        .fixedSize()
    }

    private func loadLatestBackup() {
        guard let identifier = vm.deviceIdentifier else { return }
        loadingBackupHistory = true
        DispatchQueue.global(qos: .utility).async {
            let latest = Archives.availableBackups(for: identifier).first
            DispatchQueue.main.async {
                guard vm.deviceIdentifier == identifier else { return }
                latestBackup = latest
                loadingBackupHistory = false
            }
        }
    }

    private func openRestore() {
        guard let identifier = vm.deviceIdentifier else { return }
        guard let latestBackup else {
            vm.mode = .restore
            vm.page = .prepareRestore
            return
        }
        checkingRestoreBackup = true
        DispatchQueue.global(qos: .userInitiated).async {
            let info = Archives.validateRestoreArchive(at: latestBackup.url)
            DispatchQueue.main.async {
                checkingRestoreBackup = false
                guard vm.deviceIdentifier == identifier else { return }
                guard info.verified else {
                    loadLatestBackup()
                    Archives.presentArchiveBroken(info: info)
                    return
                }
                vm.restoreLocation = latestBackup.url.path
                vm.restoreArchiveIsPasswordProtected = info.isEncrypted
                vm.restoreApplicationsCount = info.applications
                vm.restoreArchiveSystemBuildVersion = info.systemBuildVersion
                vm.mode = .restore
                vm.page = .prepareRestore
            }
        }
    }

    private var backupLocationSelection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Storage Location").font(.callout).foregroundStyle(.secondary)
            if let source {
                Text(source.url.path).textSelection(.enabled).lineLimit(3)
                Group {
                    switch source.mode {
                    case .incremental:
                        Text("A new incremental version will be created. The selected backup stays unchanged.")
                    case .resumeIncremental:
                        Text("The unfinished incremental version will continue from its previous complete snapshot.")
                    case .retryFull:
                        Text("This backup has no verified incremental checkpoint. Retrying may transfer all device data again.")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            } else if choseNewLocation {
                Text(vm.backupLocation).textSelection(.enabled).lineLimit(3)
            } else {
                Text("Choose a backup location before starting.").foregroundStyle(.secondary)
            }
            HStack {
                Menu {
                    Button("New Backup…", action: chooseNewLocation)
                    Button("Continue or Update an Existing Backup…", action: chooseExistingBackup)
                } label: {
                    Label(source == nil && !choseNewLocation ? LocalizedStringKey("Choose Backup Location") : LocalizedStringKey("Change Backup Location"), systemImage: "folder")
                }
                .fixedSize()
                .disabled(choosingLocation)
                if source != nil || choseNewLocation {
                    Button("Show In Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([source?.url ?? URL(fileURLWithPath: vm.backupLocation).deletingLastPathComponent()])
                    }
                }
            }
        }
    }

    private var tableFields: [DeviceInformationPresentation.Row] {
        let fields: [DeviceInfoField]
        switch informationCategory {
        case 1: fields = batteryInformation
        case 2: fields = storageInformation
        default: fields = deviceInformation
        }
        let readable = DeviceInformationPresentation.rows(values: Dictionary(uniqueKeysWithValues: fields.map { ($0.key, $0.value) }))
        guard !search.isEmpty else { return readable }
        return readable.filter {
            $0.title.localizedCaseInsensitiveContains(search)
                || $0.value.localizedCaseInsensitiveContains(search)
                || $0.detail.localizedCaseInsensitiveContains(search)
        }
    }

    private var informationTable: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    tableControls
                }
                VStack(alignment: .leading, spacing: 8) {
                    tableControls
                }
            }
            .padding(16)
            if pane == .applications && isReadingApplications {
                ProgressView("Reading installed apps…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if pane == .applications && applicationReadFailed {
                ContentUnavailableView {
                    Label("Could not read installed apps.", systemImage: "exclamationmark.triangle")
                } actions: {
                    Button("Retry", action: readApplications)
                }
            } else if pane == .applications {
                applicationTable
            } else {
                Table(tableFields, selection: $selectedInformation) {
                    TableColumn("Information Item") { field in
                        Text(field.title).lineLimit(2).padding(.vertical, 6)
                    }
                    .width(min: 145, ideal: 210)
                    TableColumn("Current Value") { field in
                        Text(field.value).lineLimit(2).textSelection(.enabled)
                            .help(field.value)
                    }
                    .width(min: 100, ideal: 170)
                    TableColumn("Meaning") { field in
                        Text(field.detail).font(.callout).foregroundStyle(.secondary)
                            .lineLimit(2).help(field.detail)
                    }
                    .width(min: 160, ideal: 380)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: false))
                .overlay {
                    if tableFields.isEmpty {
                        ContentUnavailableView.search(text: search)
                    }
                }
            }
        }
    }

    private var filteredApplications: [InstalledApplication] {
        guard !search.isEmpty else { return applications }
        return applications.filter {
            $0.name.localizedCaseInsensitiveContains(search)
                || $0.id.localizedCaseInsensitiveContains(search)
                || $0.version.localizedCaseInsensitiveContains(search)
        }
    }

    private var applicationTable: some View {
        Table(filteredApplications, selection: $selectedInformation) {
            TableColumn("Application") { app in
                HStack(spacing: 10) {
                    Group {
                        if let icon = app.icon {
                            Image(nsImage: icon).resizable().scaledToFit()
                        } else {
                            Image(systemName: "app.dashed")
                                .resizable().scaledToFit()
                                .foregroundStyle(.secondary)
                                .padding(3)
                        }
                    }
                    .frame(width: 28, height: 28)
                    .clipShape(.rect(cornerRadius: 6))
                    .accessibilityHidden(true)
                    Text(app.name).lineLimit(1)
                }
                .padding(.vertical, 4)
            }
            .width(min: 170, ideal: 280)
            TableColumn("Version", value: \.version)
                .width(min: 70, ideal: 100, max: 160)
            TableColumn("Bundle ID") { app in
                Text(app.id).lineLimit(1).foregroundStyle(.secondary).textSelection(.enabled)
            }
            .width(min: 130, ideal: 280)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .overlay {
            if filteredApplications.isEmpty { ContentUnavailableView.search(text: search) }
        }
    }

    @ViewBuilder private var tableControls: some View {
        if pane == .information {
            Picker("Category", selection: $informationCategory) {
                Text("Device").tag(0)
                Text("Battery").tag(1)
                Text("Storage").tag(2)
            }
            .labelsHidden()
            .fixedSize()
        } else {
            Text("Installed Apps").font(.headline)
        }
        Spacer(minLength: 0)
        TextField("Filter", text: $search)
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 140, maxWidth: 260)
    }

    private var totalCapacity: Int64? {
        storageInformation.first(where: { $0.key == "TotalDiskCapacity" })
            .flatMap { Int64($0.value) }
    }

    private var availableCapacity: Int64? {
        storageInformation.first(where: { $0.key == "AmountDataAvailable" })
            .flatMap { Int64($0.value) }
    }

    private var bottomBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 24) {
                storageBar
                Spacer(minLength: 0)
                startButton
            }
            VStack(alignment: .leading, spacing: 12) {
                storageBar
                HStack { Spacer(); startButton }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.bar)
    }

    private var storageBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let total = totalCapacity, let available = availableCapacity, total > 0 {
                GeometryReader { geometry in
                    let used = min(1, max(0, Double(total - available) / Double(total)))
                    HStack(spacing: 0) {
                        Rectangle().fill(Color(nsColor: .controlAccentColor)).frame(width: geometry.size.width * used)
                        Rectangle().fill(.primary.opacity(0.08))
                    }
                    .clipShape(.rect(cornerRadius: 4))
                }
                .frame(height: 10)
                HStack {
                    Text("Used")
                    Spacer()
                    Text("Free space: \(ByteCountFormatter.string(fromByteCount: available, countStyle: .file))")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Label("USB", systemImage: "cable.connector")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 180, maxWidth: .infinity)
    }

    private var startButton: some View {
        HStack(spacing: 8) {
            if choosingLocation { ProgressView().controlSize(.small) }
            Button(action: startBackup) {
                Group {
                    if choosingLocation {
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
                .padding(.horizontal, 12)
            }
            .disabled(!canStartBackup)
            .help(canStartBackup ? "Start Backup" : "Choose a backup location before starting.")
        }
        .fixedSize()
    }

    private func readAdditionalInformation() {
        guard !didReadInformation, let udid = vm.deviceIdentifier else { return }
        didReadInformation = true
        isReadingBattery = true
        DispatchQueue.global(qos: .utility).async {
            let manager = AppleMobileDeviceManager.shared
            let values = manager.readLockdownValues(udid: udid, domains: [
                "com.apple.mobile.battery", "com.apple.disk_usage", "com.apple.mobile.backup",
            ], connection: .usb)
            let battery = DeviceInfoField.rows(from: values["com.apple.mobile.battery"]?.value)
            let storage = DeviceInfoField.rows(from: values["com.apple.disk_usage"]?.value)
            let backup = values["com.apple.mobile.backup"]?.value as? [String: Any]
            let encrypted = backup?["WillEncrypt"] as? Bool
            DispatchQueue.main.async {
                guard vm.deviceIdentifier == udid else { return }
                isReadingBattery = false
                batteryInformation = battery
                storageInformation = storage
                encryptionStatus = encrypted.map { $0 ? .enabled : .disabled } ?? .unknown
                vm.backupEncrypted = encrypted ?? false
            }
        }
    }

    private func refreshBattery() {
        guard didReadInformation, !isReadingBattery, !encryptionInProgress,
              let udid = vm.deviceIdentifier else { return }
        isReadingBattery = true
        DispatchQueue.global(qos: .utility).async {
            let battery = DeviceInfoField.rows(from: AppleMobileDeviceManager.shared.readFromLockdown(
                udid: udid, domain: "com.apple.mobile.battery", connection: .usb
            )?.value)
            DispatchQueue.main.async {
                isReadingBattery = false
                guard vm.deviceIdentifier == udid else { return }
                // A failed request must not present an old percentage as a fresh reading.
                batteryInformation = battery
            }
        }
    }

    private func readApplications() {
        guard !didReadApplications, !isReadingApplications, let udid = vm.deviceIdentifier else { return }
        isReadingApplications = true
        applicationReadFailed = false
        let progress = Progress(totalUnitCount: 0)
        iconReadProgress?.cancel()
        iconReadProgress = progress
        DispatchQueue.global(qos: .utility).async {
            let manager = AppleMobileDeviceManager.shared
            let apps = manager.listApplications(udid: udid, connection: .usb, includeIcons: false)
            let records = apps?.map { identifier, data -> InstalledApplication in
                let values = data.value as? [String: AnyCodable]
                let name = values?["CFBundleDisplayName"]?.value as? String ?? identifier
                let version = values?["CFBundleShortVersionString"]?.value as? String ?? "—"
                return InstalledApplication(id: identifier, name: name, version: version)
            }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } ?? []
            progress.totalUnitCount = Int64(records.count)
            DispatchQueue.main.async {
                guard vm.deviceIdentifier == udid, !progress.isCancelled else { progress.cancel(); return }
                applications = records
                isReadingApplications = false
                didReadApplications = apps != nil
                applicationReadFailed = apps == nil
            }
            guard apps != nil else { return }
            manager.readApplicationIcons(udid: udid, identifiers: records.map(\.id), progress: progress) { identifier, data in
                guard !progress.isCancelled,
                      let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
                      let thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, [
                          kCGImageSourceThumbnailMaxPixelSize: 64,
                          kCGImageSourceCreateThumbnailFromImageAlways: true,
                          kCGImageSourceCreateThumbnailWithTransform: true,
                          kCGImageSourceShouldCacheImmediately: true,
                      ] as CFDictionary) else { return }
                let image = NSImage(cgImage: thumbnail, size: NSSize(width: 28, height: 28))
                DispatchQueue.main.async {
                    guard vm.deviceIdentifier == udid, !progress.isCancelled else { return }
                    applications.first(where: { $0.id == identifier })?.icon = image
                }
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
            return "Binary data (\(data.count) bytes)"
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

@Observable
private final class InstalledApplication: Identifiable {
    let id: String
    let name: String
    let version: String
    var icon: NSImage?

    init(id: String, name: String, version: String) {
        self.id = id
        self.name = name
        self.version = version
    }
}
