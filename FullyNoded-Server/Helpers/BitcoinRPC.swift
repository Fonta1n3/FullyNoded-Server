//
//  MakeRPCCall.swift
//  StandUp
//
//  Created by Peter on 03/06/20.
//  Copyright © 2020 Peter. All rights reserved.
//

import Foundation

class BitcoinRPC {
    
    static let shared = BitcoinRPC()
    lazy var session = URLSession(configuration: .default)
    
    func command(method: String, params: [String: Any], completion: @escaping ((result: Any?, error: String?)) -> Void) {
        let port = UserDefaults.standard.string(forKey: "port") ?? "8332"
        
        let nodeIp = "127.0.0.1:\(port)"
        let user = UserDefaults.standard.string(forKey: "rpcuser") ?? "FullyNoded-Server"
        
        DataManager.retrieve(entityName: .rpcCreds) { [weak self] creds in
            guard let self = self else { return }
            
            guard let creds = creds else {
                completion((nil, "No BitcoinRPCCreds saved."))
                return
            }
            
            guard let encryptedPass = creds["password"] as? Data else {
                completion((nil, "No rpc password saved."))
                return
            }
            
            guard let decryptedPass = Crypto.decrypt(encryptedPass) else {
                completion((nil, "Unable to decrypt the rpc password."))
                return
            }
            
            guard let rpcPassword = String(data: decryptedPass, encoding: .utf8) else {
                completion((nil, "Unable to encode rpc password data to utf8 string."))
                return
            }
            
            var stringUrl = "http://\(user):\(rpcPassword)@\(nodeIp)"
            if method == "rescanblockchain" {
                stringUrl += "/wallet/jm_wallet"
            }
            guard let url = URL(string: stringUrl) else {
                completion((nil, "Error converting the url."))
                return
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
            
            let dict:[String:Any] = ["jsonrpc": "1.0", "id": UUID().uuidString, "method": method, "params": params]
            
            guard let jsonData = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted) else {
                #if DEBUG
                print("converting to jsonData failing...")
                #endif
                return
            }
            
            request.httpBody = jsonData
            
            let task = session.dataTask(with: request as URLRequest) { (data, response, error) in
                guard let urlContent = data else {
                    completion((nil, error?.localizedDescription))
                    return
                }
                
                guard let json = try? JSONSerialization.jsonObject(with: urlContent, options: .mutableLeaves) as? NSDictionary else {
                    if let httpResponse = response as? HTTPURLResponse {
                        switch httpResponse.statusCode {
                        case 401:
                            completion((nil, "Looks like your rpc credentials are incorrect, please double check them. If you changed your rpc creds in your bitcoin.conf you need to restart your node for the changes to take effect."))
                        case 503:
                            completion(("", nil))
                        case 403:
                            completion((nil, "Http error 403, this usually means you are trying to use an rpc command (\(method)) which is not included in your bitcoin.conf rpcwhitelist. See Bitcoin Core debug.log for details."))
                        default:
                            completion((nil, "Unable to decode the response from your node, http status code: \(httpResponse.statusCode)"))
                        }
                    } else {
                        completion((nil, "Unable to decode the response from your node..."))
                    }
                    return
                }
                
                #if DEBUG
                print("json: \(json)")
                #endif
                
                guard let errorCheck = json["error"] as? NSDictionary else {
                    completion((json["result"], nil))
                    return
                }
                
                guard let errorMessage = errorCheck["message"] as? String else {
                    completion((nil, "Uknown error from bitcoind"))
                    return
                }
                
                completion((nil, errorMessage))
            }
            task.resume()
        }
    }
}
