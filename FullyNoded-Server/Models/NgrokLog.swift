//
//  NgrokLog.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 10/10/24.
//

import Foundation

//   let ngrokLog = try? JSONDecoder().decode(NgrokLog.self, from: jsonData)


// MARK: - NgrokLog
struct NgrokLog: Codable {
    let addr, lvl, msg, name: String?
    let obj, t, url: String?
}
