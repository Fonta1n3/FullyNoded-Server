//
//  CoreData.swift
//  FullyNoded-Server
//
//  Created by Peter Denton on 9/11/24.
//

import Foundation

import CoreData
import Foundation

/// Main data manager to handle the todo items
class DataManager: NSObject {
    static let shared = DataManager()
    /// Dynamic properties that the UI will react to
    //@Published var credentials: [RPCCredentials] = [RPCCredentials]()
    
    /// Add the Core Data container with the model name
    let container: NSPersistentContainer = NSPersistentContainer(name: "FullyNoded_Server")
    
    /// Default init method. Load the Core Data container
    override init() {
        super.init()
        container.loadPersistentStores { _, _ in }
    }
    
    class func retrieve(entityName: Entity, completion: @escaping (([String:Any]?)) -> Void) {
        let context = DataManager.shared.container.viewContext
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName.rawValue)
        fetchRequest.returnsObjectsAsFaults = false
        fetchRequest.resultType = .dictionaryResultType
        
        do {
            if let results = try context.fetch(fetchRequest) as? [[String:Any]], results.count > 0 {
                completion(results[0])
            } else {
                completion(nil)
            }
            
        } catch {
            completion(nil)
        }
    }
    
    
    class func deleteAllData(entityName: Entity, completion: @escaping ((Bool)) -> Void) {
        let context = DataManager.shared.container.viewContext
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName.rawValue)
        fetchRequest.returnsObjectsAsFaults = false
        
        do {
            let stuff = try? context.fetch(fetchRequest)
            
            for thing in stuff as! [NSManagedObject] {
                context.delete(thing)
            }
            
            try context.save()
            
            completion(true)
            
        } catch {
            completion(false)
        }
    }
    
    class func saveEntity(entityName: Entity, dict: [String:Any], completion: @escaping ((Bool)) -> Void) {
        let context = DataManager.shared.container.viewContext
        
        guard let entity = NSEntityDescription.entity(forEntityName: entityName.rawValue, in: context) else {
            completion(false)
            return
        }
        
        let credential = NSManagedObject(entity: entity, insertInto: context)
        var success = false
        
        for (key, value) in dict {
            credential.setValue(value, forKey: key)
            do {
                try context.save()
                success = true
            } catch {
                success = false
            }
        }
        
        completion(success)
    }
    
    class func update(keyToUpdate: String, newValue: Any, entity: Entity, completion: @escaping ((Bool)) -> Void) {
        let context = DataManager.shared.container.viewContext
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: entity.rawValue)
        fetchRequest.returnsObjectsAsFaults = false
        
        guard let results = try? context.fetch(fetchRequest), results.count > 0 else {
            completion(false)
            return
        }
        
        results[0].setValue(newValue, forKey: keyToUpdate)
        
        do {
            try context.save()
            completion(true)
        } catch {
            completion(false)
        }
    }
}
