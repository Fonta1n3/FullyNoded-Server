//
//  LatestBtcCoreRelease.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 9/5/24.
//

import Foundation

enum LatestBtcCoreRelease {
        
    static func get(completion: @escaping ((releases: TaggedReleases?, error: String?)) -> Void) {
        let url = "https://api.github.com/repos/bitcoin/bitcoin/releases"
        // https://api.github.com/repos/ElementsProject/lightning/releases
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
                completion((nil, "No data returned from GitHub API when fetching latest Bitcoin Core release."))
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
