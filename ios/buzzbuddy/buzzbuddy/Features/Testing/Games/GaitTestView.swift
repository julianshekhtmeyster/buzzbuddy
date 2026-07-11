//
//  GaitTestView.swift
//  buzzbuddy
//
//  Created by Max DeWeese on 7/11/26.
//


import SwiftUI

struct GaitTestView: View {
    
    @EnvironmentObject var engine: TestEngine
    
    @StateObject private var recorder = MotionRecorder()
    
    @State private var countdown = 5
    @State private var isCountingDown = false
    @State private var isRecording = false
    @State private var completed = false
    
    
    var body: some View {
        
        VStack(spacing: 30) {
            
            Text("Walking")
                .font(.largeTitle)
                .bold()
            
            
            if isCountingDown {
                
                Text("\(countdown)")
                    .font(.system(size: 80))
                
                Text("Get ready...")
            }
            
            
            else if isRecording {
                
                Text("Walk Forward 10 Steps")
                    .font(.title)
                
                Text("Hold your phone firmly against your chest")
                
                ProgressView()
            }
            
            
            else if completed {
                
                Text("Complete")
                    .font(.largeTitle)
                
            }
            
            
            else {
                
                Text("""
                Hold your phone firmly against your chest.
                
                Walk forward naturally for 10 seconds.
                """)
                .multilineTextAlignment(.center)
                
                
                Button {
                    startCountdown()
                } label: {
                    Text("Start Test")
                        .font(.title2)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
    
    
    private func startCountdown() {
        
        isCountingDown = true
        countdown = 5
        
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            
            countdown -= 1
            
            if countdown == 0 {
                timer.invalidate()
                
                isCountingDown = false
                startRecording()
            }
        }
    }
    
    
    private func startRecording() {
        
        isRecording = true
        
        recorder.startRecording()
        
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            finishRecording()
        }
    }
    
    
    private func finishRecording() {
        
        recorder.stopRecording()
        
        let data = GaitTestData(
            timestamp: Date(),
            duration: recorder.duration,
            acceleration: recorder.acceleration,
            rotation: recorder.rotation,
            pitch: recorder.pitch,
            roll: recorder.roll
        )
        
        
        GaitDataManager.save(
            data,
            baseline: engine.isBaseline
        )
        
        
        completed = true
        isRecording = false
        
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            
            engine.completeGame(score: 0)
        }
    }
}
