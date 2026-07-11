//
//  AddEventView.swift
//  buzzbuddy
//
//  Created by Max DeWeese on 7/10/26.
//

import SwiftUI

struct AddEventView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Add Event")
                    .font(.title2)
                    .fontWeight(.semibold)

                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 32, height: 32)
                    }

                    Spacer()
                }
                .padding(.leading, 12)
            }
            .padding(.top, 24)
            .padding(.bottom, 14)

            ScrollView {
                content
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var content: some View {
        Text("Event form goes here")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.top, 40)
    }
}

#Preview {
    NavigationStack {
        AddEventView()
    }
}
