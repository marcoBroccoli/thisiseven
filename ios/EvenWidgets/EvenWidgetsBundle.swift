import WidgetKit
import SwiftUI

@main
struct EvenWidgetsBundle: WidgetBundle {
    var body: some Widget {
        // Home screen
        BalanceWidget()          // small — Balance
        BalanceUpNextWidget()    // medium — Balance + Up Next
        ThisWeekWidget()         // large — This Week
        TodayWidget()            // small — Today (dark card)
        UpNextWidget()           // small — Up Next
        // Lock screen (inline / circular / rectangular)
        LockWidget()
    }
}
