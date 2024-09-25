// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let welcome = try? JSONDecoder().decode(Welcome.self, from: jsonData)

import Foundation

typealias TaggedReleases = [TaggedReleaseElement]

struct TaggedReleaseElement: Codable, Identifiable, Hashable {
    let uuid = UUID()
    let url, assetsURL: String?
    let uploadURL: String?
    let htmlURL: String?
    let id: Int?
    let author: Author?
    let nodeID, tagName, targetCommitish, name: String?
    let draft, prerelease: Bool?
    let createdAt, publishedAt: String?
    let tarballURL, zipballURL: String?
    let body: String?
    
    public func hash(into hasher: inout Hasher) {
        return hasher.combine(uuid)
    }
    
    public static func == (lhs: TaggedReleaseElement, rhs: TaggedReleaseElement) -> Bool {
        return lhs.uuid == rhs.uuid
    }

    enum CodingKeys: String, CodingKey {
        case url
        case assetsURL = "assets_url"
        case uploadURL = "upload_url"
        case htmlURL = "html_url"
        case id, author
        case nodeID = "node_id"
        case tagName = "tag_name"
        case targetCommitish = "target_commitish"
        case name, draft, prerelease
        case createdAt = "created_at"
        case publishedAt = "published_at"
        case tarballURL = "tarball_url"
        case zipballURL = "zipball_url"
        case body
    }
}

// MARK: - Author
struct Author: Codable {
    let login: String?
    let id: Int?
}
