import Dependencies
import EvenCore
import Foundation
import WidgetClient
#if canImport(WidgetKit)
    import WidgetKit
#endif

extension WidgetClient: DependencyKey {
    public static let liveValue = WidgetClient(
        publish: { snapshot in
            snapshot.write()
            #if canImport(WidgetKit)
                WidgetCenter.shared.reloadAllTimelines()
            #endif
        }
    )
}
