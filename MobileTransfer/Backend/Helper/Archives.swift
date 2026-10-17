//
//  Archives.swift
//  MobileTransfer
//
//  Created by 秋星桥 on 2024/10/10.
//

import Cocoa
import Foundation
import UniformTypeIdentifiers

enum Archives {
    struct ArchiveInfo {
        let url: URL
        let verified: Bool
        let deviceIdentifier: String
        let isEncrypted: Bool
        let systemBuildVersion: String
        let applications: Int
        let failureReason: String?

        init(
            url: URL,
            verified: Bool,
            deviceIdentifier: String,
            isEncrypted: Bool,
            systemBuildVersion: String,
            applications: Int,
            failureReason: String?
        ) {
            self.url = url
            self.verified = verified
            self.deviceIdentifier = deviceIdentifier
            self.isEncrypted = isEncrypted
            self.systemBuildVersion = systemBuildVersion
            self.applications = applications
            self.failureReason = failureReason
        }

        static func broken(at: URL, reason: String) -> ArchiveInfo {
            ArchiveInfo(
                url: at,
                verified: false,
                deviceIdentifier: "",
                isEncrypted: false,
                systemBuildVersion: "",
                applications: 0,
                failureReason: reason
            )
        }
    }
}

extension Archives {
    static func beginVerification() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowsOtherFileTypes = false
        panel.canCreateDirectories = true

        if let type = UTType("tech.nootag.itm.backup") {
            panel.allowedContentTypes = [type]
        } else {
            assertionFailure()
        }

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return }

        let info = validateRestoreArchive(at: url)
        if info.verified {
            presentArchiveValid(info: info)
        } else {
            presentArchiveBroken(info: info)
        }
    }

    static func convertFromBBackupp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowsOtherFileTypes = false
        panel.canCreateDirectories = true

        let response = panel.runModal()
        guard response == .OK, let selectedURL = panel.url else { return }

        let devicePlist = selectedURL.appendingPathComponent("Device.plist")
        guard let deviceData = try? Data(contentsOf: devicePlist) else {
            presentConvertFailed(info: NSLocalizedString("Unable to read from Device.plist", comment: ""))
            return
        }

        let device = try? PropertyListDecoder().decode(Device.self, from: deviceData)
        guard let device else {
            presentConvertFailed(info: NSLocalizedString("Unable to decode Device.plist", comment: ""))
            return
        }

        let udid = device.udid
        guard !udid.isEmpty else {
            presentConvertFailed(info: NSLocalizedString("UDID is empty", comment: ""))
            return
        }

        let backupLocationWithUDID = selectedURL.appendingPathComponent(udid)
        let info = validateRestoreArchive(at: backupLocationWithUDID)
        guard info.verified else {
            presentConvertFailed(info: String(format:
                NSLocalizedString("Unable to validate archive at %@: %@", comment: ""),
                backupLocationWithUDID.path,
                info.failureReason ?? NSLocalizedString("Unknown error", comment: "")))
            return
        }

        let contents = try? FileManager.default.contentsOfDirectory(atPath: backupLocationWithUDID.path)
        guard var contents else {
            presentConvertFailed(info: NSLocalizedString("Unable to list contents of backup location", comment: ""))
            return
        }
        contents = contents
            .filter { !$0.hasPrefix("._") }
            .filter { $0 != ".DS_Store" }

        guard !contents.contains(where: { FileManager.default.fileExists(atPath: selectedURL.appendingPathComponent($0).path) }) else {
            presentConvertFailed(info: NSLocalizedString("File conflict with convert", comment: ""))
            return
        }

        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Convert BBackupp Archive", comment: "")
        alert.informativeText = String(format:
            NSLocalizedString("Convert BBackupp archive for %@ to iTM format?", comment: ""),
            device.deviceName)
        alert.addButton(withTitle: NSLocalizedString("Convert In Place", comment: ""))
        alert.buttons.first?.hasDestructiveAction = true
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        alert.alertStyle = .warning

        let resp = alert.runModal()
        guard resp == .alertFirstButtonReturn else { return }

        var errors: [Error] = []
        for item in contents {
            do {
                let src = backupLocationWithUDID.appendingPathComponent(item)
                let dst = selectedURL.appendingPathComponent(item)
                try FileManager.default.moveItem(at: src, to: dst)
            } catch {
                errors.append(error)
            }
        }
        do {
            try FileManager.default.removeItem(at: backupLocationWithUDID)
        } catch {
            errors.append(error)
        }

        guard errors.isEmpty else {
            presentConvertFailed(info: String(format:
                NSLocalizedString("Failed to operate files: %@", comment: ""),
                errors.first?.localizedDescription ?? ""))
            return
        }

        // because of the sandbox we can only put items inside this directory
        let name = selectedURL
            .deletingPathExtension()
            .lastPathComponent
        let mobiletransfer = selectedURL
            .appendingPathComponent(name)
            .appendingPathExtension(".mobiletransfer")

        do {
            var contents = try FileManager.default.contentsOfDirectory(atPath: selectedURL.path)
            contents = contents
                .filter { !$0.hasPrefix("._") }
                .filter { $0 != ".DS_Store" }
            try FileManager.default.createDirectory(at: mobiletransfer, withIntermediateDirectories: true)
            for item in contents {
                let src = selectedURL.appendingPathComponent(item)
                let dst = mobiletransfer.appendingPathComponent(item)
                try FileManager.default.moveItem(at: src, to: dst)
            }
        } catch {
            presentConvertFailed(info: error.localizedDescription)
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([mobiletransfer])

        let newInfo = validateRestoreArchive(at: mobiletransfer)
        if newInfo.verified {
            presentArchiveValid(info: newInfo)
        } else {
            presentArchiveBroken(info: newInfo)
        }
    }

    static func validateRestoreArchive(at url: URL) -> ArchiveInfo {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
            return .broken(at: url, reason: NSLocalizedString("File not found", comment: ""))
        }
        guard isDir.boolValue else {
            return .broken(at: url, reason: NSLocalizedString("Selected file is not a directory", comment: ""))
        }

        let infoPlist = url.appendingPathComponent("Info.plist")
        guard FileManager.default.fileExists(atPath: infoPlist.path) else {
            return .broken(at: url, reason: NSLocalizedString("Info.plist not found", comment: ""))
        }
        guard let info = NSDictionary(contentsOf: infoPlist) as? [String: Any] else {
            return .broken(at: url, reason: NSLocalizedString("Info.plist not readable", comment: ""))
        }
        guard let systemBuildVersion = info["Build Version"] as? String else {
            return .broken(at: url, reason: NSLocalizedString("Unable to determine system build version", comment: ""))
        }
        guard let deviceIdentifier = info["Unique Identifier"] as? String else {
            return .broken(at: url, reason: NSLocalizedString("Unable to determine device identifier", comment: ""))
        }

        let statusPlist = url.appendingPathComponent("Status.plist")
        guard FileManager.default.fileExists(atPath: statusPlist.path) else {
            return .broken(at: url, reason: NSLocalizedString("Status.plist not found", comment: ""))
        }

        guard let status = NSDictionary(contentsOf: statusPlist) as? [String: Any] else {
            return .broken(at: url, reason: NSLocalizedString("Status.plist not readable", comment: ""))
        }
        guard let snapshotState = status["SnapshotState"] as? String else {
            return .broken(at: url, reason: NSLocalizedString("Unable to determine snapshot status", comment: ""))
        }
        guard snapshotState.lowercased() == "finished" else {
            return .broken(at: url, reason: NSLocalizedString("Snapshot not finished", comment: ""))
        }

        let manifestPlist = url.appendingPathComponent("Manifest.plist")
        guard FileManager.default.fileExists(atPath: manifestPlist.path) else {
            return .broken(at: url, reason: NSLocalizedString("Manifest.plist not found", comment: ""))
        }
        guard let manifest = NSDictionary(contentsOf: manifestPlist) as? [String: Any] else {
            return .broken(at: url, reason: NSLocalizedString("Manifest.plist not readable", comment: ""))
        }
        let restoreArchiveIsPasswordProtected = manifest["IsEncrypted"] as? Bool ?? false

        let url = url.appendingPathComponent("Applications")
        let restoreApplicationsCount = (try? FileManager.default.contentsOfDirectory(atPath: url.path))?.count ?? 0

        return .init(
            url: url,
            verified: true,
            deviceIdentifier: deviceIdentifier,
            isEncrypted: restoreArchiveIsPasswordProtected,
            systemBuildVersion: systemBuildVersion,
            applications: restoreApplicationsCount,
            failureReason: nil
        )
    }
}

extension Archives {
    static func presentArchiveValid(info: ArchiveInfo) {
        assert(info.verified)

        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Verified Archive", comment: "")
        if info.applications > 0 {
            alert.informativeText = String(format:
                NSLocalizedString("The selected archive looks validate and contains %d applications.", comment: ""),
                info.applications)
        } else {
            alert.informativeText = NSLocalizedString("The selected archive looks validate.", comment: "")
        }
        alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        alert.alertStyle = .informational
        alert.runModal()
    }

    static func presentArchiveBroken(info: ArchiveInfo) {
        assert(!info.verified)

        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Invalid Archive", comment: "")
        if let reason = info.failureReason, !reason.isEmpty {
            alert.informativeText = String(
                format: NSLocalizedString("The selected archive is invalid or corrupted. %@", comment: ""),
                reason
            )
        } else {
            alert.informativeText = NSLocalizedString("The selected archive is invalid or corrupted.", comment: "")
        }
        alert.addButton(withTitle: NSLocalizedString("Move to Trash", comment: ""))
        alert.buttons.first?.hasDestructiveAction = true
        alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        alert.alertStyle = .critical
        let resp = alert.runModal()
        if resp == .alertFirstButtonReturn {
            try? FileManager.default.trashItem(at: info.url, resultingItemURL: nil)
        }
    }

    static func presentConvertFailed(info: String) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Convert Failed", comment: "")
        alert.informativeText = info
        alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        alert.alertStyle = .critical
        alert.runModal()
    }

    enum MigrateError: Error {
        case cancelled
        case unableToVerifyBackup
        case deviceIdentifierMismatch
        case other(Error)

        var localizedDescription: String {
            switch self {
            case .cancelled:
                NSLocalizedString("Cancelled", comment: "")
            case .unableToVerifyBackup:
                NSLocalizedString("Unable to verify backup", comment: "")
            case .deviceIdentifierMismatch:
                NSLocalizedString("Unable to load checkpoint from another device", comment: "")
            case let .other(error):
                error.localizedDescription
            }
        }
    }

    static func migrateTo(location: URL, completion: @escaping (Result<Void, MigrateError>) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowsOtherFileTypes = false
        panel.canCreateDirectories = true

        if let type = UTType("tech.nootag.itm.backup") {
            panel.allowedContentTypes = [type]
        } else {
            assertionFailure()
        }

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else {
            completion(.failure(.cancelled))
            return
        }

        let info = validateRestoreArchive(at: url)
        guard info.verified else {
            completion(.failure(.unableToVerifyBackup))
            return
        }

//      works with increment backup by test, so allow user to do this
//      guard info.deviceIdentifier == udid else {
//          completion(.failure(.deviceIdentifierMismatch))
//          return
//      }

        DispatchQueue.global().async {
            migrateEx(fromLocation: url, toLocation: location, completion: completion)
        }
    }

    private static func migrateEx(
        fromLocation: URL,
        toLocation: URL,
        completion: @escaping (Result<Void, MigrateError>) -> Void
    ) {
        var executeError: MigrateError?
        defer {
            sleep(1)
            DispatchQueue.main.async {
                if let executeError {
                    completion(.failure(executeError))
                } else {
                    completion(.success(()))
                }
            }
        }

        do {
            let content = try FileManager.default.contentsOfDirectory(atPath: fromLocation.path)
            for item in content where !item.hasPrefix(".") {
                let src = fromLocation.appendingPathComponent(item)
                let dst = toLocation.appendingPathComponent(item)
                try linkOrCopyItem(at: src, to: dst)
            }
        } catch {
            executeError = .other(error)
        }
    }

    private static func linkOrCopyItem(at src: URL, to dst: URL) throws {
        do {
            try FileManager.default.linkItem(at: src, to: dst)
        } catch {
            try FileManager.default.copyItem(at: src, to: dst)
        }
    }
}
