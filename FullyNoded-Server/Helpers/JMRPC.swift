//
//  JMRPC.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 10/14/24.
//

import Foundation

class JMRPC {
    
    static let sharedInstance = JMRPC()
    let torClient = TorClient.sharedInstance
    private var attempts = 0
    private var token:String?
    private var isNostr = false
    
    private init() {}
    
    func command(method: JM_REST, param: [String:Any]?, completion: @escaping ((response: Any?, errorDesc: String?)) -> Void) {
        attempts += 1
        
        //var paramToUse:[String:Any] = [:]
//        if let param = param {
//            paramToUse = param
//        }
            
            
                            
            let walletUrl = "https://localhost:28183/\(method.stringValue)"
            
            guard let url = URL(string: walletUrl) else {
                completion((nil, "url error"))
                return
            }
            
            var request = URLRequest(url: url)
            var timeout = 10.0
            var httpMethod = "GET"
            
//            if !paramToUse.isEmpty {
//                guard let jsonData = try? JSONSerialization.data(withJSONObject: paramToUse) else {
//                    completion((nil, "Unable to encode your params into json data."))
//                    return
//                }
//                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
//                request.setValue("\(jsonData.count)", forHTTPHeaderField: "Content-Length")
//                request.httpBody = jsonData
//            }
            
            request.timeoutInterval = timeout
            request.httpMethod = httpMethod
            request.url = url
            
#if DEBUG
            print("url = \(url)")
            print("httpMethod = \(String(describing: httpMethod))")
            print("self.token = \(String(describing: self.token))")
            //print("httpBody = \(paramToUse)")
#endif
            
            
        let task = URLSession.shared.dataTask(with: request as URLRequest) { [weak self] (data, response, error) in
                guard let self = self else { return }
                
                guard let urlContent = data else {
                    
                    guard let error = error else {
                        if self.attempts < 20 {
                            self.command(method: method, param: param, completion: completion)
                        } else {
                            self.attempts = 0
                            completion((nil, "Unknown error, ran out of attempts"))
                        }
                        
                        return
                    }
                    
                    if self.attempts < 20 {
                        self.command(method: method, param: param, completion: completion)
                    } else {
                        self.attempts = 0
#if DEBUG
                        print("error: \(error.localizedDescription)")
#endif
                        completion((nil, error.localizedDescription))
                    }
                    
                    return
                }
                
                self.attempts = 0
                
                guard let json = try? JSONSerialization.jsonObject(with: urlContent, options: .mutableLeaves) as? NSDictionary else {
                    if let httpResponse = response as? HTTPURLResponse {
                        print("httpResponse.statusCode: \(httpResponse.statusCode)")
                    } else {
                        completion((nil, "Unable to decode the response..."))
                    }
                    return
                }
                
#if DEBUG
                print("json: \(json)")
#endif
                
                guard let message = json["message"] as? String else {
                    completion((json, nil))
                    return
                }
                
                completion((nil, message))
            }
            
            task.resume()
    }
}
