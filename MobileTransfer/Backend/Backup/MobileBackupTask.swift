//
//  MobileBackupTask.swift
//  BBackupp
//
//  Created by 秋星桥 on 2024/3/8.
//

import AppleMobileDeviceLibrary
import AuxiliaryExecute
import Combine
import Darwin
import Foundation
import Observation

private let dateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd-HHmmss"
    formatter.locale = .init(identifier: "en_US_POSIX")
    return formatter
}()

private let ignoredKeywords = [
    "Receiving files",
]

@Observable
class MobileBackupTask: Identifiable {
    var id: UUID = .init()
    let date: Date = .init()

    struct Configuration: Codable, CopyableCodable {
        let device: Device
        let useNetwork: Bool
        let useStoreBase: URL
    }

    let config: Configuration

    @ObservationIgnored
    var cancellable: Set<AnyCancellable> = []

    @ObservationIgnored
    let throttledSubject = PassthroughSubject<Void, Never>()

    init(config: Configuration) {
        self.config = config.codableCopy()!
        throttledSubject
            .throttle(for: .seconds(0.2), scheduler: DispatchQueue.global(), latest: true)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                // Touch observable properties to notify observers
                _output = _output
            }
            .store(in: &cancellable)
    }

    struct Log: Identifiable {
        var id: UUID = .init()
        let date: Date = .init()
        let text: String
    }

    @ObservationIgnored
    private var _output: [Log] = []
    var output: [Log] {
        get {
            access(keyPath: \.output)
            return _output
        }
        set {
            withMutation(keyPath: \.output) {
                _output = newValue
            }
            throttledSubject.send()
        }
    }

    @ObservationIgnored
    private var _overall: Progress = .init()
    var overall: Progress {
        get {
            access(keyPath: \.overall)
            return _overall
        }
        set {
            guard _overall != newValue else { return }
            withMutation(keyPath: \.overall) {
                _overall = newValue
            }
            throttledSubject.send()
        }
    }

    @ObservationIgnored
    private var _current: Progress = .init()
    var current: Progress {
        get {
            access(keyPath: \.current)
            return _current
        }
        set {
            guard _current != newValue else { return }
            withMutation(keyPath: \.current) {
                _current = newValue
            }
            throttledSubject.send()
        }
    }

    enum BackupError: Error {
        case unknown
        case deviceNotFound
        case interrupted
        case unexpectedExitCode
        case terminated
        case archiveInUse
    }

    var error: BackupError?
    var hasStartedTransfer = false
    var currentSourceName: String?

    @ObservationIgnored
    private var applicationNames: [String: String]?

    enum BackupStatus {
        case initialized
        case executing
        case completed
    }

    var status: BackupStatus = .initialized
    var executing: Bool {
        status == .executing || pid != nil
    }

    var completed: Bool {
        [.completed].contains(status)
    }

    var success: Bool {
        error == nil
    }

    var pid: pid_t?
    var recp: AuxiliaryExecute.ExecuteReceipt?

    func start() {
        guard status == .initialized else { return }
        status = .executing
        executeStart()
    }

    func terminate() {
        requiresMainThread { self.error = .terminated }
        defer { decodeOutput("Terminated by request.\n") }
        guard let pid else { return }
        kill(pid, SIGKILL)
    }

    private func executeStart() {
        assert(!Thread.isMainThread)

        overall.totalUnitCount = 100
        current.totalUnitCount = 100

        defer {
            sleep(1)
            decodeOutput("\n\n\n")
            requiresMainThread {
                self.pid = nil
                if self.error == nil,
                   self.overall.completedUnitCount != self.overall.totalUnitCount
                {
                    self.overall.totalUnitCount = 100
                    self.overall.completedUnitCount = 100
                }
                self.status = .completed
            }
        }

        do {
            try FileManager.default.createDirectory(
                at: config.useStoreBase,
                withIntermediateDirectories: true
            )
        } catch {
            decodeOutput("Could not create backup directory: \(error)\n")
            requiresMainThread { self.error = .unknown }
            return
        }

        let lockPath = config.useStoreBase.appendingPathComponent(".itm.lock").path
        let archiveLock = open(lockPath, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard archiveLock >= 0 else {
            decodeOutput("Could not lock backup directory.\n")
            requiresMainThread { self.error = .archiveInUse }
            return
        }
        defer { close(archiveLock) }
        guard flock(archiveLock, LOCK_EX | LOCK_NB) == 0 else {
            decodeOutput("Backup directory is already in use.\n")
            requiresMainThread { self.error = .archiveInUse }
            return
        }

        let args = config.decodeBinaryCommand()
        decodeOutput("\(Self.mobileBackupExecutable)\n")
        decodeOutput("Core Version: \(Self.mobileBackupVersion)\n")
        decodeOutput("Core Command: \(args)\n")

        let link = config.useStoreBase.appendingPathComponent(config.device.udid)
        let target = config.useStoreBase
        do {
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) != nil {
                try FileManager.default.removeItem(at: link)
            } else if FileManager.default.fileExists(atPath: link.path) {
                throw CocoaError(.fileWriteFileExists)
            }
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        } catch {
            decodeOutput("failed to create link: \(error)\n")
            DispatchQueue.main.asyncAndWait {
                self.error = .unknown
            }
            return
        }
        defer { try? FileManager.default.removeItem(at: link) }

        decodeOutput("starting command...\n")
        let recp = AuxiliaryExecute.spawn(
            command: Self.mobileBackupExecutable,
            args: args,
            environment: [:],
            timeout: -1
        ) { pid in
            requiresMainThread { self.pid = pid }
        } output: { output in
            self.decodeOutput(output)
        }
        decodeOutput("\n\n\n")
        decodeOutput("Result: \(recp.exitCode)\n")

        requiresMainThread { self.decodeReceipt(recp) }
    }

    // MARK: OUTPUT HANDLER

    private func decodeReceipt(_ recp: AuxiliaryExecute.ExecuteReceipt) {
        self.recp = recp
        if recp.exitCode != 0, error == nil {
            error = .unexpectedExitCode
        } else if error == nil {
            overall.totalUnitCount = 100
            overall.completedUnitCount = 100
        }
        status = .completed
    }

    @ObservationIgnored
    private var buffer = ""
    private func decodeOutput(_ output: String) {
        buffer += output
        buffer = buffer.replacingOccurrences(of: "\r", with: "\n")
        guard buffer.contains("\n") else { return }
        var lineBuffer = ""
        let copyBuffer = buffer
        buffer = ""
        for char in copyBuffer {
            if char == "\n" || char == "\r" {
                decodeLine(lineBuffer)
                lineBuffer = ""
            } else {
                lineBuffer.append(char)
            }
        }
        if !lineBuffer.isEmpty { buffer = lineBuffer }
    }

    private func decodeLine(_ input: String) {
        let line = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }

        if line == "ITM_BATCH_START" || line == "ITM_BATCH_END" {
            requiresMainThread {
                if line == "ITM_BATCH_START" { self.hasStartedTransfer = true }
                self.current = .init()
                self.currentSourceName = nil
            }
            return
        }

        if line.hasPrefix("ITM_DOMAIN_HEX:") {
            let encoded = line.dropFirst("ITM_DOMAIN_HEX:".count)
            guard let domain = Self.decodeDomain(encoded) else { return }
            let name = sourceName(for: domain)
            requiresMainThread { self.currentSourceName = name }
            return
        }

        // overall progress found
        if line.hasPrefix("["), line.contains("]"), line.hasSuffix("Finished") {
            guard let cutA = line.components(separatedBy: "]").last?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let cutB = cutA.components(separatedBy: "%").first,
                  let value = Int(cutB),
                  value >= 0, value <= 100
            else { return }
            let prog = Progress(totalUnitCount: 100)
            prog.completedUnitCount = Int64(value)
            guard overall != prog else { return }
            requiresMainThread { self.overall = prog }
            return
        }

        // partial progress found
        if line.hasPrefix("["), line.contains("]"), line.contains("("), line.contains(")"), line.contains("/") {
            guard let cutA = line.components(separatedBy: "(").last,
                  let currentValue = cutA.components(separatedBy: "/").first,
                  let cutB = line.components(separatedBy: ")").first,
                  let totalValue = cutB.components(separatedBy: "/").last,
                  let curr = SizeDecoder.decode(currentValue),
                  let total = SizeDecoder.decode(totalValue)
            else { return }
            let prog = Progress(totalUnitCount: Int64(total))
            prog.completedUnitCount = Int64(curr)
            guard current != prog else { return }
            requiresMainThread {
                self.hasStartedTransfer = true
                self.current = prog
            }
            return
        }

        for keyword in ignoredKeywords where line.contains(keyword) {
            return
        }

        guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        NSLog("[BackupTask] \(id) \(line)")
        requiresMainThread { self.output.append(.init(text: line)) }
    }

    private static func decodeDomain(_ encoded: Substring) -> String? {
        let hex = Array(encoded.utf8)
        guard !hex.isEmpty, hex.count <= 400, hex.count.isMultiple(of: 2) else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(hex.count / 2)
        for offset in stride(from: 0, to: hex.count, by: 2) {
            guard let high = UInt8(String(decoding: [hex[offset]], as: UTF8.self), radix: 16),
                  let low = UInt8(String(decoding: [hex[offset + 1]], as: UTF8.self), radix: 16)
            else { return nil }
            bytes.append(high << 4 | low)
        }
        return String(bytes: bytes, encoding: .utf8)
    }

    private func sourceName(for domain: String) -> String {
        if domain == "CameraRollDomain" { return String(localized: "Photos") }
        if domain == "MediaDomain" { return String(localized: "Media") }
        if domain == "AppDataDomain" { return String(localized: "App data") }
        if domain.hasPrefix("AppDomain-") {
            let identifier = String(domain.dropFirst("AppDomain-".count))
            if applicationNames == nil { applicationNames = loadApplicationNames() }
            return applicationNames?[identifier] ?? identifier
        }
        if domain.hasPrefix("AppDomainGroup-") || domain.hasPrefix("AppDomainPlugin-") {
            return String(localized: "Shared app data")
        }
        return String(localized: "System data")
    }

    private func loadApplicationNames() -> [String: String] {
        let infoURL = config.useStoreBase.appendingPathComponent("Info.plist")
        guard let info = NSDictionary(contentsOf: infoURL) as? [String: Any],
              let applications = info["Applications"] as? [String: [String: Any]]
        else { return [:] }

        var names: [String: String] = [:]
        for (identifier, application) in applications {
            guard let data = application["iTunesMetadata"] as? Data,
                  let metadata = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let name = metadata["itemName"] as? String,
                  !name.isEmpty
            else { continue }
            names[identifier] = name
        }
        return names
    }
}

extension MobileBackupTask {
    static let mobileBackupExecutable = Bundle.main.url(forAuxiliaryExecutable: "MobileBackup")!.path
    static let mobileBackupVersion: String = {
        var stdout = AuxiliaryExecute.spawn(
            command: mobileBackupExecutable,
            args: ["-v"]
        ).stdout
        if stdout.hasPrefix("idevicebackup2") {
            stdout.removeFirst("idevicebackup2".count)
        }
        stdout = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return stdout
    }()
}

extension MobileBackupTask.Configuration {
    func decodeBinaryCommand() -> [String] {
        var ans = [String]()
        ans += ["-u", device.udid]
        if useNetwork { ans += ["-n"] }
        let status = NSDictionary(contentsOf: useStoreBase.appendingPathComponent("Status.plist"))
        if (status?["SnapshotState"] as? String)?.lowercased() == "uploading",
           !Archives.hasIncrementalMarker(at: useStoreBase)
        {
            ans += ["--full"]
        }
        ans += ["backup"]
        ans += [useStoreBase.path]
        return ans
    }
}
