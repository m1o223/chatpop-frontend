import { useEffect, useId, useLayoutEffect, useRef, useState } from 'react'
import { Check, ChevronLeft, MessageCircle, Search, Settings, SquarePen, X } from 'lucide-react'
import { isNativeIOS, NativeChatControls } from './nativeChatControls'
import './ChatDrawer.css'
import { PaywallScreen, SettingsScreen } from './SettingsScreen'
import { CreativeStudioCard } from './CreativeStudioCard'

type HistoryItem = { id: string; title: string }
type ChatDrawerProps = {
  chats: HistoryItem[]
  activeId: string
  onSelect: (id: string) => void
  onNewChat: () => void
  onClose: () => void
}

const sampleChats: HistoryItem[] = [
  { id: 'sample-trip', title: 'Plan my trip' },
  { id: 'sample-code', title: 'Explain this code' },
  { id: 'sample-ideas', title: 'Image ideas' },
]

export function ChatDrawer(props: ChatDrawerProps) {
  return isNativeIOS ? <NativeChats {...props} /> : <WebChats {...props} />
}

function NativeChats(props: ChatDrawerProps) {
  const latest = useRef(props)
  useLayoutEffect(() => { latest.current = props }, [props])
  const [error, setError] = useState(false)
  useEffect(() => {
    let cancelled = false
    let started = false
    const timer = window.setTimeout(() => {
      started = true
      const current = latest.current
      NativeChatControls.showChats({ chats: current.chats, activeId: current.activeId }).then((result) => {
        if (cancelled) return
        const callbacks = latest.current
        if (/^[0-9a-f-]{36}$/i.test(result.selectedId)) callbacks.onSelect(result.selectedId)
        callbacks.onClose()
        if (result.action === 'newChat' || !result.selectedId) callbacks.onNewChat()
      }).catch(() => { if (!cancelled) setError(true) })
    }, 0)
    return () => {
      cancelled = true
      window.clearTimeout(timer)
      if (started) void NativeChatControls.closeChats().catch(() => {})
    }
  }, [])
  return error ? <div className="native-error" role="alert"><p>Chats unavailable</p><button onClick={props.onClose}>Back to chat</button></div> : null
}

function WebChats({ chats, activeId, onSelect, onNewChat, onClose }: ChatDrawerProps) {
  const [destination, setDestination] = useState<'paywall' | 'settings' | null>(null)
  const dialog = useRef<HTMLDialogElement>(null)
  const animation = useRef<Animation | null>(null)
  const closeStarted = useRef(false)
  const latestClose = useRef(onClose)
  useLayoutEffect(() => { latestClose.current = onClose }, [onClose])
  const [closing, setClosing] = useState(false)
  const [query, setQuery] = useState('')
  const [selectedId, setSelectedId] = useState(activeId)
  const [searching, setSearching] = useState(false)
  const searchInput = useRef<HTMLInputElement>(null)
  const history = useRef<HTMLElement>(null)
  useEffect(() => { if (searching) searchInput.current?.focus() }, [searching])
  useEffect(() => { if (query) history.current?.scrollIntoView({ block: 'start' }) }, [query])
  const titleId = useId()
  const historyId = useId()
  const entries = [...chats, ...sampleChats].filter((item) =>
    item.title.toLocaleLowerCase().includes(query.trim().toLocaleLowerCase()))

  useLayoutEffect(() => {
    const element = dialog.current
    if (!element) return
    const previousFocus = document.activeElement
    closeStarted.current = false
    element.style.transform = 'translateX(-100%)'
    element.showModal()
    const opening = element.animate(
      [{ transform: 'translateX(-100%)' }, { transform: 'translateX(0)' }],
      drawerTiming(),
    )
    animation.current = opening
    opening.onfinish = () => {
      if (animation.current !== opening) return
      element.style.transform = 'none'
      opening.cancel()
      animation.current = null
    }
    return () => {
      animation.current?.cancel()
      animation.current = null
      element.close()
      if (previousFocus instanceof HTMLElement) previousFocus.focus({ preventScroll: true })
    }
  }, [])

  function close(action?: () => void) {
    const element = dialog.current
    if (!element || closeStarted.current) return
    closeStarted.current = true
    setClosing(true)
    // Reverse from the visible position even if the opening animation is still running.
    const currentTransform = getComputedStyle(element).transform
    element.style.transform = currentTransform
    animation.current?.cancel()
    const exiting = element.animate(
      [{ transform: currentTransform }, { transform: 'translateX(-100%)' }],
      drawerTiming(),
    )
    animation.current = exiting
    exiting.onfinish = () => {
      if (animation.current !== exiting) return
      element.style.transform = 'translateX(-100%)'
      exiting.cancel()
      animation.current = null
      // React removes the top-layer dialog only after its page has left the screen.
      latestClose.current()
      action?.()
    }
  }

  return (
    <dialog
      ref={dialog}
      className={`chat-drawer${closing ? ' is-closing' : ''}`}
      aria-labelledby={titleId}
      onCancel={(event) => { event.preventDefault(); close() }}
      onClick={(event) => {
        if (event.target !== event.currentTarget) return
        const rect = event.currentTarget.getBoundingClientRect()
        if (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom) close()
      }}
    >
      <header className="drawer-header">
        <h2 id={titleId}>CHATPOP</h2>
        <button type="button" className="icon-button" aria-label="Settings" title="Settings" onClick={() => setDestination('settings')}><Settings size={22} /></button>
        <button type="button" className="icon-button" aria-label="Close chats" title="Close chats" onClick={() => close()}><ChevronLeft size={22} /></button>
      </header>

      <div className="drawer-content">
      <div className="drawer-subscription">
        <div><strong>Try ChatPop Plus or Pro</strong><p>Unlock more features</p></div>
        <button onClick={() => setDestination('paywall')}>Try Now</button>
      </div>
      <CreativeStudioCard paused={destination !== null || closing} />
      <section ref={history} className="drawer-history" aria-labelledby={historyId}>
        <div className="drawer-history-heading"><h3 id={historyId}>Chats</h3><button type="button" className="drawer-new-chat icon-button" aria-label="New chat" title="New chat" onClick={() => close(onNewChat)}><SquarePen size={20} /></button></div>
        <ul>
          {entries.map((item) => (
            <li key={item.id}>
              <button
                type="button"
                className={`drawer-history-row${item.id === selectedId ? ' is-selected' : ''}`}
                aria-pressed={item.id === selectedId}
                onClick={() => {
                  setSelectedId(item.id)
                  if (chats.some((chat) => chat.id === item.id)) onSelect(item.id)
                }}
              >
                <MessageCircle size={18} aria-hidden="true" />
                <span>{item.title}</span>
                {item.id === selectedId && <Check size={17} className="drawer-check" aria-hidden="true" />}
              </button>
            </li>
          ))}
        </ul>
        {entries.length === 0 && <p className="drawer-empty" role="status">No chats found</p>}
      </section>
      </div>
      <footer className="drawer-search-dock">
        {searching ? <label className="drawer-search"><Search size={18} aria-hidden="true" /><input ref={searchInput} type="search" aria-label="Search chats" placeholder="Search chats" value={query} onChange={(event) => setQuery(event.target.value)} /><button className="icon-button" aria-label="Close search" onClick={() => { setQuery(''); setSearching(false) }}><X size={18} /></button></label>
          : <button className="drawer-search-toggle" onClick={() => setSearching(true)}><Search size={18} /><span>Search</span></button>}
      </footer>
      {destination === 'paywall' && <PaywallScreen onClose={() => setDestination(null)} />}
      {destination === 'settings' && <SettingsScreen onClose={() => setDestination(null)} />}
    </dialog>
  )
}

function drawerTiming(): KeyframeAnimationOptions {
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches
  return {
    duration: reducedMotion ? 160 : 360,
    easing: reducedMotion ? 'ease-out' : 'cubic-bezier(0.32, 0.72, 0, 1)',
    fill: 'both',
  }
}
