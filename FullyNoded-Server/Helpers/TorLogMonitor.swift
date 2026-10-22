//
//  TorLogMonitor.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 11/22/25.
//
//  The end of tor's notices.log, refreshed while it's on screen. Only the last part of the file
//  is read: tor appends to it for as long as the app has been in use.
//

import SwiftUI
import Combine

class TorLogMonitor: ObservableObject {
    struct Line: Identifiable, Equatable {
        /// Position from the start of the tail, so repeated lines stay distinct.
        let id: Int
        let text: String
    }

    @Published private(set) var lines: [Line] = []
    private var cancellable: AnyCancellable?
    private let maxLines = 200

    init() {
        startMonitoring()
    }

    private func startMonitoring() {
        reloadLog()
        cancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.reloadLog()
            }
    }

    private func reloadLog() {
        let path = "\(Torrc.torPath())/notices.log"
        let maxLines = self.maxLines
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var tail: [String] = []
            if let handle = FileHandle(forReadingAtPath: path) {
                defer { try? handle.close() }
                let size = (try? handle.seekToEnd()) ?? 0
                let chunk: UInt64 = 64 * 1024
                try? handle.seek(toOffset: size > chunk ? size - chunk : 0)
                if let data = try? handle.readToEnd() {
                    let text = String(decoding: data, as: UTF8.self)
                    var all = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
                    if size > chunk, !all.isEmpty { all.removeFirst() } // likely cut mid-line
                    tail = Array(all.suffix(maxLines))
                }
            }
            let lines = tail.enumerated().map { Line(id: $0.offset, text: $0.element) }
            DispatchQueue.main.async {
                guard let self = self, self.lines != lines else { return }
                self.lines = lines
            }
        }
    }

    deinit { cancellable?.cancel() }
}
