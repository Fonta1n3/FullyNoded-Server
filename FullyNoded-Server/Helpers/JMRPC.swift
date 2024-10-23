//
//  JMRPC.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 10/14/24.
//

import Foundation

class JMRPC: NSObject, URLSessionDelegate {
    
    static let sharedInstance = JMRPC()
    //let torClient = TorClient.sharedInstance
   // private var attempts = 0
    private var token:String?
    //private var isNostr = false
    private lazy var sessionConfiguration: URLSessionConfiguration = .default

    // The tor client url session including the tor configuration.
    lazy var session = URLSession(configuration: sessionConfiguration)
    
    private override init() {}
    
    func command(method: JM_REST, param: [String:Any]?, completion: @escaping ((response: Any?, errorDesc: String?)) -> Void) {
        //attempts += 1
        
        //var paramToUse:[String:Any] = [:]
//        if let param = param {
//            paramToUse = param
//        }
            
        session = URLSession(configuration: sessionConfiguration, delegate: self, delegateQueue: .main)
                            
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
            
            
        let task = session.dataTask(with: request as URLRequest) { [weak self] (data, response, error) in
                guard let self = self else { return }
                
                guard let urlContent = data else {
                    
                    guard let error = error else {
                        completion((nil, "Unknown error."))
                        
                        return
                    }
                    
#if DEBUG
                        print("error: \(error.localizedDescription)")
#endif
                        completion((nil, error.localizedDescription))
                    
                    return
                }
                                
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
    
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        print("did receive challenge")
        guard let trust = challenge.protectionSpace.serverTrust else {
            return
        }
        
        let credential = URLCredential(trust: trust)
        
//        if let certData = self.cert,
//            let remoteCert = SecTrustGetCertificateAtIndex(trust, 0) {
//            let remoteCertData = SecCertificateCopyData(remoteCert) as NSData
//            let certData = Data(base64Encoded: certData)
//
//            if let pinnedCertData = certData,
//                remoteCertData.isEqual(to: pinnedCertData as Data) {
//                print("using cert")
//                completionHandler(.useCredential, credential)
//            } else {
//                completionHandler(.rejectProtectionSpace, nil)
//            }
//        } else {
//            print("using cert")
//            completionHandler(.useCredential, credential)
//        }
        
        completionHandler(.useCredential, credential)
    }
}
