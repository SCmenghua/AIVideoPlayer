import SwiftUI

/// Tab 外壳。每个 Tab 拥有自己的 NavigationStack；
/// 系统 Tab Bar 在 iOS 26 上原生呈现 Liquid Glass 外观。
struct RootView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var environment = environment

        TabView(selection: $environment.selectedTab) {
            NavigationStack {
                HomeView()
            }
            .tabItem { Label(AppTab.browser.title, systemImage: AppTab.browser.systemImage) }
            .tag(AppTab.browser)

            NavigationStack {
                PlayerView()
            }
            .tabItem { Label(AppTab.player.title, systemImage: AppTab.player.systemImage) }
            .tag(AppTab.player)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label(AppTab.settings.title, systemImage: AppTab.settings.systemImage) }
            .tag(AppTab.settings)
        }
    }
}
