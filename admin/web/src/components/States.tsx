import type { ReactNode } from 'react'

/** The three things a data surface can be. Every table and panel in the
 *  console routes through these, so "no rows yet" never looks like "broken"
 *  and neither ever looks like a blank card. */

export function Loading({ rows = 6, cols = 4 }: { rows?: number; cols?: number }) {
  return (
    <div aria-busy="true" aria-label="Loading">
      {Array.from({ length: rows }).map((_, r) => (
        <div className="skeleton-row" key={r}>
          {Array.from({ length: cols }).map((_, c) => (
            <div
              className="skeleton-bar"
              key={c}
              style={{ maxWidth: c === 0 ? '28%' : c === cols - 1 ? '12%' : '20%' }}
            />
          ))}
        </div>
      ))}
    </div>
  )
}

export function Empty({
  title = 'Nothing here',
  detail,
  action,
}: {
  title?: string
  detail?: string
  action?: ReactNode
}) {
  return (
    <div className="state">
      <div className="title">{title}</div>
      {detail && <div>{detail}</div>}
      {action && <div style={{ marginTop: 12 }}>{action}</div>}
    </div>
  )
}

export function ErrorState({ message, onRetry }: { message: string; onRetry?: () => void }) {
  return (
    <div className="state error" role="alert">
      <div className="title">Could not load this</div>
      <div>{message}</div>
      {onRetry && (
        <div style={{ marginTop: 12 }}>
          <button onClick={onRetry}>Try again</button>
        </div>
      )}
    </div>
  )
}

/** Wraps a body in the loading / error / empty decision so pages stop
 *  hand-writing the same three-branch ternary. */
export function Async<T>({
  state,
  isEmpty,
  empty,
  skeletonRows,
  skeletonCols,
  children,
}: {
  state: { data: T | null; error: string | null; loading: boolean; initial: boolean; reload: () => void }
  isEmpty?: (data: T) => boolean
  empty?: ReactNode
  skeletonRows?: number
  skeletonCols?: number
  children: (data: T) => ReactNode
}) {
  if (state.error && !state.data) return <ErrorState message={state.error} onRetry={state.reload} />
  if (state.initial || (state.loading && !state.data))
    return <Loading rows={skeletonRows} cols={skeletonCols} />
  if (!state.data) return <Empty />
  if (isEmpty?.(state.data)) return <>{empty ?? <Empty />}</>
  return <>{children(state.data)}</>
}
