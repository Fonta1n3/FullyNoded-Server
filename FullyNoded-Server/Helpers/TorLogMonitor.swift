//
//  TorLogMonitor.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 11/22/25.
//

import SwiftUI
import Combine

class TorLogMonitor: ObservableObject {
    @Published var lines: [String] = []
    private var cancellable: AnyCancellable?
    
    init() {
        startMonitoring()
    }
    
    private func startMonitoring() {
        reloadLog()
        
        cancellable = Timer.publish(every: 0.7, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.reloadLog()
            }
    }
    
    private func reloadLog() {
        let url = URL(fileURLWithPath: "\(Torrc.torPath())/notices.log")
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return }
        
        let allLines = text.components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .suffix(100)
        
        if Set(lines) != Set(allLines) {
            lines = Array(allLines)
        }
    }
    
    deinit { cancellable?.cancel() }
}
