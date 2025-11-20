//
//  ProfileCard.swift
//  Axial Mobile
//
//  Created by Matthew Sinex on 11/20/25.
//

import SwiftUI
import Auth0

struct ProfileCard: View {
    let user: UserInfo?
    
    var body: some View {
        VStack(spacing: 16) {
            if let picture = user?.picture {
                AsyncImage(url: picture) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.gray)
                }
                .frame(width: 100, height: 100)
                .clipShape(Circle())
                
                VStack(spacing: 8) {
                    if let name = user?.name {
                        Text(name).font(.title2).fontWeight(.semibold)
                    }
                    if let email = user?.email {
                        Text(email).foregroundColor(.secondary)
                    }
                }
            } else {
                ProgressView()
                Text("Loading profile...").foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(16)
    }
}

#Preview {
    ProfileCard(user: nil)
}
