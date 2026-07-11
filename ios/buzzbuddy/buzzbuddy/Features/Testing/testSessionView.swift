//
//  testEngine.swift
//  buzzbuddy
//
//  Created by Max DeWeese on 7/10/26.
//

import SwiftUI

struct TestSessionView: View {

    @EnvironmentObject var engine: TestEngine
    
    @State private var showDisclaimer = true
    
    
    var body: some View {
        ZStack {
            
            if showDisclaimer {
                
                VStack(spacing: 30) {
                    
                    Text("Before You Begin")
                        .font(.largeTitle)
                        .bold()
                    
                    
                    Text(
                        "This is not a medical test. It compares your performance to your normal baseline."
                    )
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .padding()
                    
                    
                    Button {
                        showDisclaimer = false
                    } label: {
                        Text("Begin")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(width: 150, height: 50)
                            .background(Color.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 15))
                    }
                }
                .padding()
                
            } else {
                
                if let game = engine.currentGame {
                    
                    ZStack {
                        
                        game.view
                        
                        VStack {
                            HStack {
                                Spacer()
                                
                                Button {
                                    exitTest()
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 36, height: 36)
                                        .background(.thinMaterial)
                                        .clipShape(Circle())
                                }
                                .padding(.top, 16)
                                .padding(.trailing, 16)
                            }
                            
                            Spacer()
                        }
                    }
                    
                } else {
                    
                    Text("Test Complete")
                    
                }
            }
        }
    }
    
    
    func exitTest() {
        engine.currentIndex = 100000
        showDisclaimer = true
    }
}
