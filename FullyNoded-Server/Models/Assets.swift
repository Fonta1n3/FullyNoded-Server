//
//  Assets.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 10/14/24.
//

import Foundation

typealias Assets = [AssetElement]

// MARK: - WelcomeElement
struct AssetElement: Codable {
    let url: String?
    let id: Int?
    let nodeID, name: String?
    let label: JSONNull?
    let uploader: Uploader?
    let contentType, state: String?
    let size, downloadCount: Int?
    let createdAt, updatedAt: Date?
    let browserDownloadURL: String?

    enum CodingKeys: String, CodingKey {
        case url, id
        case nodeID
        case name, label, uploader
        case contentType
        case state, size
        case downloadCount
        case createdAt
        case updatedAt
        case browserDownloadURL
    }
}

// MARK: - Uploader
struct Uploader: Codable {
    let login: String?
    let id: Int?
    let nodeID: String?
    let avatarURL: String?
    let gravatarID: String?
    let url, htmlURL, followersURL: String?
    let followingURL, gistsURL, starredURL: String?
    let subscriptionsURL, organizationsURL, reposURL: String?
    let eventsURL: String?
    let receivedEventsURL: String?
    let type: String?
    let siteAdmin: Bool?

    enum CodingKeys: String, CodingKey {
        case login, id
        case nodeID
        case avatarURL
        case gravatarID
        case url
        case htmlURL
        case followersURL
        case followingURL
        case gistsURL
        case starredURL
        case subscriptionsURL
        case organizationsURL
        case reposURL
        case eventsURL
        case receivedEventsURL
        case type
        case siteAdmin
    }
}


// MARK: - Encode/decode helpers

class JSONNull: Codable, Hashable {

    public static func == (lhs: JSONNull, rhs: JSONNull) -> Bool {
            return true
    }

    public var hashValue: Int {
            return 0
    }

    public init() {}

    public required init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if !container.decodeNil() {
                    throw DecodingError.typeMismatch(JSONNull.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Wrong type for JSONNull"))
            }
    }

    public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encodeNil()
    }
}



