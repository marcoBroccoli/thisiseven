#if os(iOS)
    import SwiftUI

    /// Minimal wrapping layout for chip rows (same idea as Inbox Review FlowLayout).
    struct FlowWrap: Layout {
        var spacing: CGFloat = 6

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ())
            -> CGSize
        {
            arrange(proposal: proposal, subviews: subviews).size
        }

        func placeSubviews(
            in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()
        ) {
            let result = arrange(proposal: proposal, subviews: subviews)
            for (index, frame) in result.frames.enumerated() {
                subviews[index].place(
                    at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                    proposal: ProposedViewSize(frame.size)
                )
            }
        }

        private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (
            size: CGSize, frames: [CGRect]
        ) {
            let maxWidth = proposal.width ?? .infinity
            var frames: [CGRect] = []
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0
            var maxX: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                if x + size.width > maxWidth, x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }
                frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
                maxX = max(maxX, x - spacing)
            }
            return (CGSize(width: maxX, height: y + rowHeight), frames)
        }
    }
#endif
