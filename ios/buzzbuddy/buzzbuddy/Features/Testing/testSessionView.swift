//
//  testEngine.swift
//  buzzbuddy
//
//  Created by Max DeWeese on 7/10/26.
//
import SwiftUI


struct TestSessionView: View {

    @EnvironmentObject var engine: TestEngine
    @State public var showSurvey = false
    
    var body: some View {

        VStack {
            if let game = engine.currentGame {

                Text(game.name)
                    .font(.title)

                game.view

            }

            else {

                Text("Test Complete")

            }

           

        }



    }

}
