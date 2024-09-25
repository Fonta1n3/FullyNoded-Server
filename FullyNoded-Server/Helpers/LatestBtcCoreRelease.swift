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
            
            
//                                if let latestTag = jsonArray[0] as? NSDictionary {
//                                    if let version = latestTag["tag_name"] as? String {
//                                        let processedVersion = version.replacingOccurrences(of: "v", with: "")
//                                        var arch = "arm64"
//                                        
//                                        #if arch(x86_64)
//                                            arch = "x86_64"
//                                        #endif
//                                        
//                                        let dict: [String: Any] = [
//                                            "version":"\(processedVersion)",
//                                            "binaryPrefix":"bitcoin-\(processedVersion)",
//                                            "macosBinary":"bitcoin-\(processedVersion)-\(arch)-apple-darwin.tar.gz",
//                                            "macosURL":"https://bitcoincore.org/bin/bitcoin-core-\(processedVersion)/bitcoin-\(processedVersion)-\(arch)-apple-darwin.tar.gz",
//                                            "shaURL":"https://bitcoincore.org/bin/bitcoin-core-\(processedVersion)/SHA256SUMS",
//                                            "shasumsSignedUrl":"https://bitcoincore.org/bin/bitcoin-core-\(processedVersion)/SHA256SUMS.asc"
//                                        ]
//                                        
//                                        completion((BitcoinEnvValues(dictionary: dict), nil))
//                                    }
//                                }
                            
                        
                    
                
            
        }
        task.resume()
    }
}
