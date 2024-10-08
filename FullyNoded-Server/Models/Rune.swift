//
//  Rune.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 10/8/24.
//

import Foundation
//   let rune = try? JSONDecoder().decode(Rune.self, from: jsonData)

// MARK: - Rune
struct Rune: Codable {
    let rune, uniqueID, warningUnrestrictedRune: String?

    enum CodingKeys: String, CodingKey {
        case rune
        case uniqueID = "unique_id"
        case warningUnrestrictedRune = "warning_unrestricted_rune"
    }
}
