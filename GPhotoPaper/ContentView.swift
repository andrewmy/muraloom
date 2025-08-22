import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authService: GoogleAuthService
    @EnvironmentObject var settings: SettingsModel

    var body: some View {
        VStack {
            if let user = authService.user {
                // Signed-in view
                Text("Welcome, \(user.profile?.name ?? "User")")
                    .font(.headline)
                
                // Pass the settings model to the SettingsView
                SettingsView(settings: settings)
                
                Button("Sign Out", action: {
                    authService.signOut()
                })
                .padding()
            } else {
                // Signed-out view
                Text("GPhotoPaper")
                    .font(.largeTitle)
                Text("Please sign in to continue.")
                    .font(.title2)
                
                Button("Sign In with Google", action: {
                    authService.signIn()
                })
                .padding()
            }
            
            if let errorMessage = authService.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding()
            }
        }
        .padding()
        .frame(width: 450, height: 350)
    }
}

#Preview {
    ContentView()
        .environmentObject(GoogleAuthService()) // Provide a dummy service for preview
}
