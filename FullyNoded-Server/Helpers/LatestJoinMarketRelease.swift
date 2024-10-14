//
//  LatestJoinMarketRelease.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 10/11/24.
//

import Foundation

enum LatestJoinMarketRelease {
        
    static func get(completion: @escaping ((releases: TaggedReleases?, error: String?)) -> Void) {
        let url = "https://api.github.com/repos/Joinmarket-Org/joinmarket-clientserver/releases"
        print("fetch latest release from \(url)")
        
        guard let destination = URL(string: url) else {
            completion((nil, "URL encoding error."))
            return
        }
        
        let request = URLRequest(url: destination)
        let session = URLSession.shared
        
        let task = session.dataTask(with: request) { (data, response, error) in
            guard error == nil else {
                completion((nil, error!.localizedDescription))
                return
            }
            
            guard let data = data else {
                completion((nil, "No data returned from GitHub API when fetching latest Join Market release."))
                return
            }
            
           guard let taggedReleases = try? JSONDecoder().decode(TaggedReleases.self, from: data) else {
                completion((nil, "Error encoding data to TaggedReleases."))
                return
            }
            completion((taggedReleases, nil))
        }
        task.resume()
    }
}

