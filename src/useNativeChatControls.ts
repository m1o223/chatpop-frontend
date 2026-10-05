import { useEffect, useLayoutEffect, useRef, useState } from 'react'
import type { PluginListenerHandle } from '@capacitor/core'
import { isNativeIOS, NativeChatControls } from './nativeChatControls'
import type { NativeControlEvent, NativeControlState } from './nativeChatControls'
import { providers } from './models'

export function useNativeChatControls(state: NativeControlState, onEvent: (event: NativeControlEvent) => void) {
  const latest = useRef({ state, onEvent })
  const [ready, setReady] = useState(false)
  const [error, setError] = useState(false)
  const [attempt, setAttempt] = useState(0)
  const [insets, setInsets] = useState({ top: 0, bottom: 0 })
  const { chatId, draft, model, hidden } = state

  useLayoutEffect(() => { latest.current = { state, onEvent } })

  useEffect(() => {
    if (!isNativeIOS) return
    let disposed = false
    let listener: PluginListenerHandle | undefined
    async function connect() {
      listener = await NativeChatControls.addListener('control', (event) => {
        if (disposed) return
        if (event.type === 'layout') {
          if (Number.isFinite(event.top) && Number.isFinite(event.bottom)) {
            setInsets({ top: Math.max(0, event.top), bottom: Math.max(0, event.bottom) })
          }
        } else latest.current.onEvent(event)
      })
      if (disposed) { await listener.remove(); return }
      await NativeChatControls.configure({
        ...latest.current.state,
        providers: providers.map(({ name, description }) => ({ name, description })),
      })
      if (!disposed) setReady(true)
    }
    void connect().catch((reason: unknown) => {
      if (!disposed) {
        console.error('Native chat controls failed to initialize', reason)
        setError(true)
        void NativeChatControls.hide().catch(() => {})
      }
    })
    return () => {
      disposed = true
      void listener?.remove().catch(() => {})
      void NativeChatControls.hide().catch(() => {})
    }
  }, [attempt])

  useEffect(() => {
    if (!isNativeIOS || !ready) return
    let disposed = false
    void NativeChatControls.updateState({ chatId, draft, model, hidden }).catch((reason: unknown) => {
      if (disposed) return
      console.error('Native chat state synchronization failed', reason)
      setReady(false)
      setError(true)
      void NativeChatControls.hide().catch(() => {})
    })
    return () => { disposed = true }
  }, [ready, chatId, draft, model, hidden])

  return { ready, error, insets, retry: () => {
    setReady(false)
    setError(false)
    setAttempt((value) => value + 1)
  } }
}
