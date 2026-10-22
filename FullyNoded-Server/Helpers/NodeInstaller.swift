//
//  NodeInstaller.swift
//  FullyNoded-Server
//
//  Installs Bitcoin Core or Bitcoin Knots for the Setup Assistant, the same way the release
//  pages do (TaggedReleasesBitcoinCoreView / TaggedReleasesBitcoinKnotsView):
//
//  1. bitcoin.conf: ConfigureCore / ConfigureKnots.checkForExistingConf (new conf, or the
//     existing one with a fresh rpcauth for FN-Server).
//  2. Download the macOS tarball, SHA256SUMS and SHA256SUMS.asc into ~/.fullynoded/<impl>.
//  3. Open Terminal with the installer script: it checks the tarball's SHA-256 against
//     SHA256SUMS, unpacks it and ad-hoc codesigns the binaries.
//  4. Wait for bitcoind to appear, then save the env (version, prefix, chain) to Core Data.
//

import Foundation

enum NodeImplementation: String, CaseIterable, Identifiable {
    case core, knots

    var id: String { rawValue }

    var name: String { self == .core ? "Bitcoin Core" : "Bitcoin Knots" }

    /// Folder under the FN-Server data directory holding the binaries.
    var folder: String { self == .core ? "BitcoinCore" : "BitcoinKnots" }

    var entity: Entity { self == .core ? .bitcoinEnv : .bitcoinKnotsEnv }

    var startScript: SCRIPT { self == .core ? .startBitcoin : .startKnots }

    /// Networks the implementation's pages can switch between.
    var chains: [String] { self == .core ? ["main", "test", "testnet4", "signet", "regtest"] : ["main", "test", "signet", "regtest"] }

    static var selected: NodeImplementation {
        (UserDefaults.standard.value(forKey: "useKnots") as? Bool ?? false) ? .knots : .core
    }

    static var arch: String {
        #if arch(x86_64)
        return "x86_64"
        #else
        return "arm64"
        #endif
    }

    /// bitcoind of an installed `prefix` (e.g. "bitcoin-28.1").
    func bitcoindPath(prefix: String) -> String {
        "\(Defaults.shared.fnDataDir)/\(folder)/\(prefix)/bin/bitcoind"
    }

    /// The saved env, if this implementation was installed and its binary is still there.
    func installedEnv(completion: @escaping (BitcoinEnvValues?) -> Void) {
        DataManager.retrieve(entityName: entity) { dict in
            guard let dict = dict,
                  let prefix = dict["prefix"] as? String, !prefix.isEmpty,
                  dict["version"] is String, dict["binaryName"] is String,
                  dict["dataDir"] is String, dict["chain"] is String,
                  FileManager.default.fileExists(atPath: bitcoindPath(prefix: prefix)) else {
                completion(nil)
                return
            }
            completion(BitcoinEnvValues(dictionary: dict))
        }
    }
}

final class NodeInstaller: NSObject, ObservableObject {

    enum Stage: Equatable {
        case idle
        case preparing
        case downloading(file: String, progress: Double)
        /// Terminal is checking the hash and unpacking.
        case verifying
        case installed(version: String)
        case failed(String)
    }

    @Published private(set) var stage: Stage = .idle
    @Published private(set) var releases: TaggedReleases = []
    @Published private(set) var releasesError: String?
    @Published private(set) var isFetchingReleases = false

    private var progressObservation: NSKeyValueObservation?
    private var pollTimer: Timer?
    /// The installer scripts append to this log (tee -a); read from `logOffset` on.
    private let logPath = "\(ConfigureCore.fnServerDir)/fullynoded.log"
    private var logOffset: UInt64 = 0

    deinit {
        pollTimer?.invalidate()
    }

    var isBusy: Bool {
        switch stage {
        case .preparing, .downloading, .verifying: return true
        default: return false
        }
    }

    // MARK: - Releases

    func fetchReleases(for implementation: NodeImplementation) {
        isFetchingReleases = true
        releasesError = nil
        let completion: ((releases: TaggedReleases?, error: String?)) -> Void = { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isFetchingReleases = false
                guard let releases = result.releases, !releases.isEmpty else {
                    self.releasesError = result.error ?? "No releases found."
                    return
                }
                // Stable releases first; release candidates stay available further down.
                self.releases = releases.filter { $0.prerelease != true && $0.draft != true }
                    + releases.filter { $0.prerelease == true && $0.draft != true }
            }
        }
        switch implementation {
        case .core: LatestBtcCoreRelease.get(completion: completion)
        case .knots: LatestBtcKnotsRelease.get(completion: completion)
        }
    }

    // MARK: - Install

    /// The download URL shown before installing.
    static func tarballURL(for release: TaggedReleaseElement, implementation: NodeImplementation) -> String? {
        guard let files = files(for: release, implementation: implementation) else { return nil }
        return files.tarball
    }

    private static func files(for release: TaggedReleaseElement, implementation: NodeImplementation) -> (version: String, tarball: String, sums: String, sig: String)? {
        guard let tagName = release.tagName, !tagName.isEmpty else { return nil }
        let version = tagName.replacingOccurrences(of: "v", with: "")
        let base: String
        switch implementation {
        case .core:
            base = "https://bitcoincore.org/bin/bitcoin-core-\(version)"
        case .knots:
            guard let major = version.split(separator: ".").first else { return nil }
            base = "https://bitcoinknots.org/files/\(major).x/\(version)"
        }
        return (version,
                "\(base)/bitcoin-\(version)-\(NodeImplementation.arch)-apple-darwin.tar.gz",
                "\(base)/SHA256SUMS",
                "\(base)/SHA256SUMS.asc")
    }

    /// A new bitcoin.conf takes prune / txindex from UserDefaults (Defaults.shared); an
    /// existing one keeps its own settings.
    func install(_ release: TaggedReleaseElement, implementation: NodeImplementation) {
        guard !isBusy else { return }
        guard let files = Self.files(for: release, implementation: implementation) else {
            stage = .failed("That release has no version tag.")
            return
        }
        stage = .preparing

        let configure: (Int?, @escaping (Bool) -> Void) -> Void = implementation == .core
            ? ConfigureCore.checkForExistingConf
            : ConfigureKnots.checkForExistingConf

        configure(nil) { [weak self] configured in
            guard let self else { return }
            guard configured else {
                self.fail("Couldn't write bitcoin.conf to \(Defaults.shared.bitcoinDataDir).")
                return
            }
            let directory = "\(Defaults.shared.fnDataDir)/\(implementation.folder)"
            self.download([files.tarball, files.sums, files.sig], to: directory) { [weak self] error in
                guard let self else { return }
                if let error {
                    self.fail(error)
                    return
                }
                self.launchVerifier(implementation: implementation, version: files.version)
            }
        }
    }

    private func download(_ urls: [String], to directory: String, completion: @escaping (String?) -> Void) {
        guard let first = urls.first else {
            completion(nil)
            return
        }
        guard let url = URL(string: first) else {
            completion("Invalid download URL: \(first)")
            return
        }
        do {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        } catch {
            completion("Couldn't create \(directory): \(error.localizedDescription)")
            return
        }

        let fileName = url.lastPathComponent
        DispatchQueue.main.async { self.stage = .downloading(file: fileName, progress: 0) }

        let task = URLSession.shared.downloadTask(with: url) { [weak self] location, response, error in
            guard let self else { return }
            self.progressObservation = nil
            if let error {
                completion("Downloading \(fileName) failed: \(error.localizedDescription)")
                return
            }
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                completion("Downloading \(fileName) failed (HTTP \(http.statusCode)). This release may not have a build for this Mac.")
                return
            }
            guard let location else {
                completion("Downloading \(fileName) failed.")
                return
            }
            let destination = URL(fileURLWithPath: directory).appendingPathComponent(fileName)
            do {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: location, to: destination)
            } catch {
                completion("Couldn't save \(fileName): \(error.localizedDescription)")
                return
            }
            self.download(Array(urls.dropFirst()), to: directory, completion: completion)
        }
        progressObservation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            DispatchQueue.main.async {
                self?.stage = .downloading(file: fileName, progress: progress.fractionCompleted)
            }
        }
        task.resume()
    }

    private func launchVerifier(implementation: NodeImplementation, version: String) {
        let binaryName = "bitcoin-\(version)-\(NodeImplementation.arch)-apple-darwin.tar.gz"
        let prefix = "bitcoin-\(version)"
        if implementation == .core {
            // Read elsewhere (Defaults.existingVersion / existingBinary / existingPrefix).
            let ud = UserDefaults.standard
            ud.set(prefix, forKey: "binaryPrefix")
            ud.set(binaryName, forKey: "macosBinary")
            ud.set(version, forKey: "version")
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: logPath)
        logOffset = (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
        DispatchQueue.main.async { self.stage = .verifying }

        let script: SCRIPT = implementation == .core ? .launchInstaller : .launchExtractKnots
        ScriptUtil.runScript(script: script, env: ["BINARY_NAME": binaryName, "VERSION": version], args: nil) { [weak self] _, _, errorMessage in
            guard let self else { return }
            if let errorMessage, !errorMessage.isEmpty {
                self.fail(errorMessage)
                return
            }
            DispatchQueue.main.async {
                self.waitForBinary(implementation: implementation, version: version, prefix: prefix, binaryName: binaryName)
            }
        }
    }

    /// Polls for bitcoind (Terminal unpacks it), then saves the env.
    private func waitForBinary(implementation: NodeImplementation, version: String, prefix: String, binaryName: String) {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            if let failure = self.installerFailure() {
                self.fail(failure)
                return
            }
            guard FileManager.default.fileExists(atPath: implementation.bitcoindPath(prefix: prefix)) else { return }
            timer.invalidate()
            self.saveEnv(implementation: implementation, version: version, prefix: prefix, binaryName: binaryName)
        }
    }

    private func saveEnv(implementation: NodeImplementation, version: String, prefix: String, binaryName: String) {
        let dict = [
            "binaryName": binaryName,
            "version": version,
            "prefix": prefix,
            "dataDir": Defaults.shared.bitcoinDataDir,
            "chain": Defaults.shared.chain
        ]
        DataManager.deleteAllData(entityName: implementation.entity) { [weak self] _ in
            DataManager.saveEntity(entityName: implementation.entity, dict: dict) { saved in
                guard let self else { return }
                guard saved else {
                    self.fail("\(implementation.name) is installed, but saving its settings failed.")
                    return
                }
                DispatchQueue.main.async { self.stage = .installed(version: version) }
            }
        }
    }

    /// Stops waiting for Terminal (e.g. it was closed before it finished).
    func cancelVerification() {
        guard stage == .verifying else { return }
        pollTimer?.invalidate()
        stage = .idle
    }

    /// The installer script's own failure messages, from what it logged since it launched.
    private func installerFailure() -> String? {
        guard let handle = FileHandle(forReadingAtPath: logPath) else { return nil }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: logOffset)) != nil,
              let data = try? handle.readToEnd(),
              let log = String(data: data, encoding: .utf8) else { return nil }
        if log.contains("Hashes do not match") {
            return "The download's SHA-256 doesn't match the release's SHA256SUMS, so it wasn't installed. Try again, and let us know if it keeps happening."
        }
        if log.contains("No hash exists") {
            return "The download couldn't be checked (no SHA-256 for it in SHA256SUMS), so it wasn't installed."
        }
        return nil
    }

    private func fail(_ message: String) {
        DispatchQueue.main.async {
            self.pollTimer?.invalidate()
            self.stage = .failed(message)
        }
    }
}
