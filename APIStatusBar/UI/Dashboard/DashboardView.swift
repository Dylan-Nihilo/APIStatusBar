import SwiftUI

struct DashboardView: View {
    @ObservedObject var poller: QuotaPoller
    @ObservedObject var modelStats: ModelStatsPoller
    @ObservedObject var settings: AppSettings

    @State private var hasAppeared = false
    @State private var refreshSpin = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                AccountCard(poller: poller,
                            modelStats: modelStats,
                            settings: settings)
                    .modifier(StaggeredAppear(index: 0, hasAppeared: hasAppeared))

                HeatmapView(dailyBuckets: modelStats.dailyBuckets,
                            today: Date())
                    .modifier(StaggeredAppear(index: 1, hasAppeared: hasAppeared))

                TopModelsCard(modelStats: modelStats,
                              settings: settings)
                    .modifier(StaggeredAppear(index: 2, hasAppeared: hasAppeared))
            }
            .padding(16)
        }
        .frame(width: 480, height: 380)
        .navigationTitle("用量仪表板")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    refreshSpin.toggle()
                    Task {
                        await poller.refresh()
                        await modelStats.refresh()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(refreshSpin ? 360 : 0))
                        .animation(.easeOut(duration: 0.6), value: refreshSpin)
                }
                .help("刷新")
            }
        }
        .onAppear {
            withAnimation { hasAppeared = true }
            if modelStats.dailyBuckets.isEmpty {
                Task { await modelStats.refresh() }
            }
        }
    }
}

private struct StaggeredAppear: ViewModifier {
    let index: Int
    let hasAppeared: Bool

    func body(content: Content) -> some View {
        content
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 8)
            .animation(.smooth(duration: 0.4).delay(Double(index) * 0.08),
                       value: hasAppeared)
    }
}
