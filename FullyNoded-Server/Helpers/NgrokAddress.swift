//
//  NgrokAddress.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 10/8/24.
//

import Foundation

enum NgrokAddress {
            
        static func get(completion: @escaping ((publicUrl: String?, error: String?)) -> Void) {
            let url = "https://api.ngrok.com/endpoints"
            #if DEBUG
            print("fetch endpoints from \(url)")
            #endif
            
            guard let destination = URL(string: url) else {
                completion((nil, "URL encoding error."))
                return
            }
            
            var request = URLRequest(url: destination)
            request.httpMethod = "GET"
            request.setValue("Bearer xxx", forHTTPHeaderField: "Authorization")
            request.setValue("2", forHTTPHeaderField: "Ngrok-Version")
            
            let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
                guard error == nil else {
                    completion((nil, error!.localizedDescription))
                    return
                }
                
                guard let data = data else {
                    completion((nil, "No data returned from GitHub API when fetching latest Bitcoin Core release."))
                    return
                }
                                
                guard let json = try? JSONSerialization.jsonObject(with: data, options: .mutableLeaves) as? [String: Any] else {
                    completion((nil, "Failed converting data to dict."))
                    return
                }
                
                guard let endpoints = json["endpoints"] as? [[String: Any]], endpoints.count > 0,
                        let public_url = endpoints[0]["public_url"] as? String else {
                    completion((nil, "No endpoints."))
                    return
                }
                
                completion((public_url.replacingOccurrences(of: "tcp://", with: ""), nil))
            }
            task.resume()
        }
}
