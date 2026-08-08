#if os(iOS)
    import ComposableArchitecture
    import EvenCore
    import ResetClient

    enum ResetPreviewSupport {
        /// The full partnered ritual — beam leaning Ada, partner's kind thing veiled.
        @MainActor
        static func ritual(beat: ResetReducer.Beat = .cover) -> StoreOf<ResetReducer> {
            var state = ResetReducer.State(
                summary: PreviewData.summary,
                me: PreviewData.ada,
                partner: PreviewData.umut
            )
            state.beat = beat
            return Store(initialState: state) {
                ResetReducer()
            } withDependencies: {
                $0.resetClient = .previewValue
            }
        }

        /// No partner — the kind-thing beat drops out entirely.
        @MainActor
        static func solo() -> StoreOf<ResetReducer> {
            let state = ResetReducer.State(
                summary: PreviewData.summaryEmpty,
                me: PreviewData.ada,
                partner: nil
            )
            return Store(initialState: state) {
                ResetReducer()
            } withDependencies: {
                $0.resetClient.fetch = { PreviewData.resetSummarySolo }
            }
        }
    }
#endif
