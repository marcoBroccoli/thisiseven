import { useCallback, useEffect, useRef, useState } from 'react'
import { ApiError } from '../api'

export type AsyncState<T> = {
  data: T | null
  error: string | null
  loading: boolean
  /** True only for the very first load — a refresh keeps the current rows on
   *  screen instead of flashing a skeleton over data the operator is reading. */
  initial: boolean
  reload: () => void
}

/** Runs `fn` on mount and whenever `deps` change, with the three states every
 *  table in this console needs. A superseded response is discarded, so typing
 *  quickly in a search box cannot land an old page over a newer one. */
export function useAsync<T>(fn: () => Promise<T>, deps: unknown[]): AsyncState<T> {
  const [data, setData] = useState<T | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [initial, setInitial] = useState(true)
  const [nonce, setNonce] = useState(0)
  const seq = useRef(0)

  const run = useCallback(() => {
    const mine = ++seq.current
    setLoading(true)
    fn()
      .then((res) => {
        if (mine !== seq.current) return
        setData(res)
        setError(null)
      })
      .catch((e: unknown) => {
        if (mine !== seq.current) return
        setError(e instanceof ApiError ? e.message : 'Something went wrong.')
      })
      .finally(() => {
        if (mine !== seq.current) return
        setLoading(false)
        setInitial(false)
      })
    // fn is re-created every render by design; deps is the real dependency set.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps)

  useEffect(run, [run, nonce])

  return { data, error, loading, initial, reload: () => setNonce((n) => n + 1) }
}

/** Debounced value — the search boxes hit the API on every keystroke otherwise. */
export function useDebounced<T>(value: T, ms = 250): T {
  const [out, setOut] = useState(value)
  useEffect(() => {
    const t = setTimeout(() => setOut(value), ms)
    return () => clearTimeout(t)
  }, [value, ms])
  return out
}
