//
//  GaitDataManager.swift
//  buzzbuddy
//
//  Created by Max DeWeese on 7/11/26.
//


import Foundation


class GaitDataManager {
    
    
    enum FileName: String {
        case baseline = "baseline_test.json"
        case recent = "recent_test.json"
    }
    
    
    
    static func save(
        _ data: GaitTestData,
        baseline: Bool
    ) {
        
        
        let file = baseline
        ? FileName.baseline
        : FileName.recent
        
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        
        do {
            
            let json = try encoder.encode(data)
            
            let url = fileURL(
                file.rawValue
            )
            
            
            // overwrite existing file
            try json.write(
                to: url,
                options: .atomic
            )
            
            
            print("Saved \(file.rawValue)")
            
        }
        catch {
            
            print(
                "Failed saving gait data:",
                error
            )
        }
    }
    
    
    
    static func load(
        baseline: Bool
    ) -> GaitTestData? {
        
        
        let file = baseline
        ? FileName.baseline
        : FileName.recent
        
        
        let url = fileURL(
            file.rawValue
        )
        
        
        guard let data = try? Data(contentsOf: url)
        else {
            return nil
        }
        
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        
        return try? decoder.decode(
            GaitTestData.self,
            from: data
        )
    }
    
    
    
    private static func fileURL(
        _ name: String
    ) -> URL {
        
        
        FileManager.default
            .urls(
                for: .documentDirectory,
                in: .userDomainMask
            )[0]
            .appendingPathComponent(name)
    }
}
