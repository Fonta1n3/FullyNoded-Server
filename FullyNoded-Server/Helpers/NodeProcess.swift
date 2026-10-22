//
//  NodeProcess.swift
//  FullyNoded-Server
//
//  Whether bitcoind (Core or Knots) is actually running for a data folder and network, and what
//  an unreachable RPC means while a start or stop is under way.
//
//  RPC alone can't tell: right after `bitcoind -daemon` returns, and while it shuts down, the RPC
//  port refuses connections exactly as when the node is off. bitcoind writes `bitcoind.pid` in the
//  network's folder of its data directory, so the process is checked directly (and confirmed to
//  be a bitcoind, so a stale pid file left by a crash can't fool it).
//

import Foundation
import Darwin

/// A start or stop the node's page is waiting on.
enum NodeTransition: Equatable {
    case starting(Date)
    case stopping(Date)
}

enum NodeProcess {

    /// What a refused RPC connection means.
    enum Unreachable {
        /// bitcoind is running but its RPC isn't up yet (or just launched).
        case starting
        /// bitcoind is still running after a stop was asked for.
        case stopping
        /// Off.
        case stopped
        /// A start was asked for, but bitcoind isn't running.
        case failedToStart
    }

    /// bitcoind's network folder: the data directory itself for mainnet, a subfolder otherwise.
    static func networkDirectory(dataDir: String, chain: String) -> String {
        switch chain {
        case "test": return dataDir + "/testnet3"
        case "testnet4": return dataDir + "/testnet4"
        case "signet": return dataDir + "/signet"
        case "regtest": return dataDir + "/regtest"
        default: return dataDir
        }
    }

    /// The pid of the bitcoind using this data folder and network, if it's running.
    static func runningPID(dataDir: String, chain: String) -> pid_t? {
        let pidFile = networkDirectory(dataDir: dataDir, chain: chain) + "/bitcoind.pid"
        guard let text = try? String(contentsOfFile: pidFile, encoding: .utf8),
              let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 0 else { return nil }
        // Alive (EPERM also means it exists), and really a bitcoind (pids are reused).
        guard kill(pid, 0) == 0 || errno == EPERM else { return nil }
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let path = String(cString: buffer)
        return (path as NSString).lastPathComponent == "bitcoind" ? pid : nil
    }

    static func isRunning(dataDir: String, chain: String) -> Bool {
        runningPID(dataDir: dataDir, chain: chain) != nil
    }

    /// How long after Start bitcoind may take to launch before it's considered not started
    /// (before it writes its pid file).
    static let launchGrace: TimeInterval = 30

    static func interpretUnreachable(transition: NodeTransition?, dataDir: String, chain: String) -> Unreachable {
        if isRunning(dataDir: dataDir, chain: chain) {
            if case .stopping = transition { return .stopping }
            return .starting
        }
        if case .starting(let since) = transition {
            return Date().timeIntervalSince(since) < launchGrace ? .starting : .failedToStart
        }
        return .stopped
    }
}
