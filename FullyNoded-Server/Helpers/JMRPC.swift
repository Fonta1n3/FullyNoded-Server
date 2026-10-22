//
//  JMRPC.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 10/14/24.
//
//  Talks to this Mac's JoinMarket wallet daemon (jmwalletd) over its REST API on
//  https://localhost:28183. Completions run on the main queue and are always called.
//

import Foundation

class JMRPC: NSObject, URLSessionDelegate {
    
    static let sharedInstance = JMRPC()
    static let port = 28183

    /// One session for the app's lifetime (a session per call was never invalidated, so each
    /// poll leaked one along with its delegate).
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        return URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
    }()
    
    private override init() {}
    
    func command(method: JM_REST, param: [String:Any]?, completion: @escaping ((response: Any?, errorDesc: String?)) -> Void) {
        guard let url = URL(string: "https://localhost:\(Self.port)/\(method.stringValue)") else {
            DispatchQueue.main.async { completion((nil, "url error")) }
            return
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.httpMethod = "GET"
        
#if DEBUG
        print("[jm] GET \(url)")
#endif
        
        let task = session.dataTask(with: request) { (data, response, error) in
            if let error = error {
#if DEBUG
                print("[jm] error: \(error.localizedDescription)")
#endif
                completion((nil, error.localizedDescription))
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data, options: .mutableLeaves) as? [String: Any] else {
                completion((nil, status == 0 ? "Unable to decode the response..." : "JoinMarket answered with HTTP \(status)."))
                return
            }
            
#if DEBUG
            print("[jm] json: \(json)")
#endif
            
            if let message = json["message"] as? String, !(200..<300).contains(status) || json.count == 1 {
                completion((nil, message))
                return
            }
            completion((json, nil))
        }
        task.resume()
    }
    
    /// jmwalletd uses a self-signed certificate (made by StartJm.command): trust it for this
    /// Mac's own daemon only.
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host == "localhost" || challenge.protectionSpace.host == "127.0.0.1",
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
