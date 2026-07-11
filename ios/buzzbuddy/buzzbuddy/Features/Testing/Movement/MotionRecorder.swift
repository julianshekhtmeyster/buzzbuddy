//
//  MotionRecorder.swift
//  buzzbuddy
//
//  Created by Max DeWeese on 7/11/26.
//


import Foundation
import CoreMotion


class MotionRecorder: ObservableObject {
    
    
    private let manager = CMMotionManager()
    
    
    private var startTime: Date?
    
    
    var acceleration: [[Double]] = []
    var rotation: [[Double]] = []
    
    var pitch: [Double] = []
    var roll: [Double] = []
    
    
    var duration: Double {
        
        guard let startTime else {
            return 0
        }
        
        return Date().timeIntervalSince(startTime)
    }
    
    
    
    func startRecording() {
        
        
        acceleration.removeAll()
        rotation.removeAll()
        pitch.removeAll()
        roll.removeAll()
        
        
        startTime = Date()
        
        
        manager.deviceMotionUpdateInterval = 1.0 / 100.0
        
        
        manager.startDeviceMotionUpdates(
            to: .main
        ) { motion, error in
            
            guard let motion else {
                return
            }
            
            
            let accel = motion.userAcceleration
            
            self.acceleration.append([
                accel.x,
                accel.y,
                accel.z
            ])
            
            
            let gyro = motion.rotationRate
            
            self.rotation.append([
                gyro.x,
                gyro.y,
                gyro.z
            ])
            
            
            self.pitch.append(
                motion.attitude.pitch
            )
            
            
            self.roll.append(
                motion.attitude.roll
            )
        }
    }
    
    
    
    func stopRecording() {
        
        manager.stopDeviceMotionUpdates()
    }
}
