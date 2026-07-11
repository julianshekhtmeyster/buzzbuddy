//
//  ContentView.swift
//  buzzbuddy
//
//  Created by Max DeWeese on 7/10/26.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var engine: TestEngine

    var body: some View {
        MainTabView()
        .fullScreenCover(isPresented: $engine.showingTest) {
            TestSessionView()
                    
            }
            .onChange(of: engine.finished){
                print("engine.finished changed ??? This probably means that the test finnished twin")

                if engine.finished && !engine.doForm{
                    engine.showingTest = false
                }
            }
            .onAppear {
                print("init test ????")
                engine.startTest(doFormA:true)
            }
    }

}

#Preview {
    ContentView()
}
