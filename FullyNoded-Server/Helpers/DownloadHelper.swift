//
//  DownloadHelper.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 1/21/25.
//

import Foundation

class FileDownloader {
    
    private let fileManager: FileManager
    private let session: URLSession
    
    // Initialize with FileManager and URLSession instances
    init(fileManager: FileManager = .default, session: URLSession = .shared) {
        self.fileManager = fileManager
        self.session = session
    }
    
    // Method to download a file from the given URL and save it to the specified directory
    func downloadAndSaveFile(toDirectory directoryPath: String, fromURL url: String, completion: @escaping (Bool, String) -> Void) {
        // 1. Ensure the directory exists or create it
        let directoryURL = URL(fileURLWithPath: directoryPath)
        
        do {
            // Check if the directory exists, if not, create it
            if !fileManager.fileExists(atPath: directoryURL.path) {
                try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
            }
            
            // 2. Create a URL from the given string
            guard let downloadURL = URL(string: url) else {
                completion(false, "Invalid URL")
                return
            }
            
            // 3. Start the download using URLSession
            let task = session.dataTask(with: downloadURL) { data, response, error in
                // Handle any errors
                if let error = error {
                    completion(false, "Download failed with error: \(error.localizedDescription)")
                    return
                }
                
                // Check if the data is valid
                guard let data = data else {
                    completion(false, "No data received")
                    return
                }
                
                // 4. Save the downloaded data to a file in the specified directory
                let fileName = downloadURL.lastPathComponent
                let fileURL = directoryURL.appendingPathComponent(fileName)
                
                do {
                    try data.write(to: fileURL)
                    completion(true, "File downloaded and saved to \(fileURL.path)")
                } catch {
                    completion(false, "Failed to save the file: \(error.localizedDescription)")
                }
            }
            
            // Start the download task
            task.resume()
            
        } catch {
            completion(false, "Error creating directory: \(error.localizedDescription)")
        }
    }
}

// Usage example:
//let downloader = FileDownloader()
//
//let directoryPath = "/Users/yourname/Downloads"
//let fileURL = "https://example.com/image.jpg"
//
//downloader.downloadAndSaveFile(toDirectory: directoryPath, fromURL: fileURL) { success, message in
//    if success {
//        print(message) // "File downloaded and saved to /path/to/file.jpg"
//    } else {
//        print("Error: \(message)") // Error message if failed
//    }
//}

