import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            GroupsListView()
                .tabItem { Label("Groups", systemImage: "person.3") }
            FriendsView()
                .tabItem { Label("Friends", systemImage: "person.2") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(SplitMateTheme.brandPurple)
    }
}
