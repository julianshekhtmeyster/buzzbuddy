import SwiftUI

struct HomeView: View {
    @EnvironmentObject var engine: GameSessionEngine
    @State private var showingTest = false

    var body: some View {
        NavigationStack {
            VStack {
                Button("Start Test") {
                    engine.startTest()
                    showingTest = true
                }
            }
            .fullScreenCover(isPresented: $showingTest) {
                TestSessionView()
            }
            .onChange(of: engine.finished) { _, finished in
                if finished {
                    showingTest = false
                }
            }
            .navigationTitle("Home")
        }
    }
}
