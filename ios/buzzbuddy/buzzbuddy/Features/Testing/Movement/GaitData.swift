//
//  GaitData.swift
//  buzzbuddy
//
//  Created by Max DeWeese on 7/11/26.
//


import Foundation


struct GaitTestData: Codable {
    
    let timestamp: Date
    
    let duration: Double
    
    let acceleration: [[Double]]
    
    let rotation: [[Double]]
    
    let pitch: [Double]
    
    let roll: [Double]
}
