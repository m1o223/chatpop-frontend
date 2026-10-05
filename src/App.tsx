import { useEffect, useLayoutEffect, useRef, useState } from 'react'
import type { CSSProperties } from 'react'
import { ArrowUp, AudioLines, ChevronDown, Menu, Mic, Plus, Sparkles, SquarePen, X } from 'lucide-react'
import { AttachmentMenu } from './AttachmentMenu'
import { BrandMark } from './BrandMark'
import { ChatDrawer } from './ChatDrawer'
import { ModelPanel } from './ModelPanel'
import { VoiceModal } from './VoiceModal'
import type { Model } from './models'
import { providers } from './models'
import { isNativeIOS, NativeChatControls } from './nativeChatControls'
import { accountRequest, listChats, listMessages } from './accountAPI'
import type { CloudChat, CloudMessage } from './accountAPI'
import { useNativeChatControls } from './useNativeChatControls'
import { useViewport } from './useViewport'
import './App.css'
import { applyTheme } from './preferences'
import './Appearance.css'

type Panel = 'menu' | 'models' | 'attachments' | 'microphone' | null
type Message = { id: string; text: string; role?: string }
type Chat = { id: string; messages: Message[]; draft: string; title?: string; cloud?: boolean; loaded?: boolean; more?: boolean }
const createChat = (): Chat => ({ id: crypto.randomUUID(), messages: [], draft: '' })

export default function App() {
  const [chats, setChats] = useState<Chat[]>(() => [createChat()])
  const [activeId, setActiveId] = useState<string | null>(null)
  const [model, setModel] = useState<Model>('Auto')
  const [panel, setPanel] = useState<Panel>(null)
  const [attachmentNotice, setAttachmentNotice] = useState<string | null>(null)
  const [accountStatus, setAccountStatus] = useState(isNativeIOS ? 'restoring' : 'signedOut')
  const [syncError, setSyncError] = useState<string | null>(null)
  const owner = useRef('')
  const sending = useRef(false)
  const pendingMessage = useRef<{ chatId: string; text: string; id: string } | null>(null)
  const [syncing, setSyncing] = useState(false)
  const input = useRef<HTMLTextAreaElement>(null)
  const modelTrigger = useRef<HTMLButtonElement>(null)
  const attachmentTrigger = useRef<HTMLButtonElement>(null)
  const conversation = useRef<HTMLDivElement>(null)
  const chat = chats.find((item) => item.id === activeId) ?? chats[0]!
  const canSend = chat.draft.trim().length > 0
  useViewport()
  const native = useNativeChatControls({ chatId: chat.id, draft: chat.draft, model, hidden: false }, (event) => {
    if (event.type === 'appearance') applyTheme(event.theme)
    if (event.type === 'menu') setPanel('menu')
    if (event.type === 'newChat') newChat()
    if (event.type === 'model' && providers.some((provider) => provider.name === event.model)) setModel(event.model)
    if (event.type === 'draft') {
      setChats((current) => current.map((item) => item.id === event.chatId ? { ...item, draft: event.text } : item))
    }
    if (event.type === 'send' && event.text.trim()) {
      void sendText(event.chatId, event.text)
    }
  })

  useEffect(() => {
    if (!isNativeIOS) return
    let alive = true
    async function changed(snapshot: { state: string; userId: string }) {
      if (!alive) return
      setAccountStatus(snapshot.state)
      if (snapshot.state === 'offline' || snapshot.state === 'restoring') return
      if (owner.current === snapshot.userId) return
      owner.current = snapshot.userId
      setChats([createChat()]); setActiveId(null); setSyncError(null); setPanel(null)
      if (!snapshot.userId) return
      setAccountStatus('loading')
      try {
        const result = await listChats()
        if (!alive || owner.current !== snapshot.userId) return
        setChats([createChat(), ...result.chats.map(c => ({ ...c, messages: [], draft: '', cloud: true }))])
        setAccountStatus('signedIn')
      } catch { if (alive && owner.current === snapshot.userId) { setSyncError('Could not load your chats. Please retry.'); setAccountStatus('signedIn') } }
    }
    const listener = NativeChatControls.addListener('account', snapshot => { void changed(snapshot) })
    void NativeChatControls.accountState().then(changed).catch(() => { if (alive) setSyncError('Account connection unavailable. Please retry.') })
    return () => { alive = false; void listener.then(handle => handle.remove()).catch(() => {}) }
  }, [])

  async function selectChat(id: string) {
    setActiveId(id); setAttachmentNotice(null)
    const selected = chats.find(c => c.id === id)
    if (selected && !selected.cloud) return
    const user = owner.current
    try {
      if (!selected) {
        const result = await accountRequest<{ chat: CloudChat }>('GET', `/chats/${id}`)
        if (owner.current !== user) return
        setChats(current => [...current.filter(c => c.id !== id), { ...result.chat, messages: [], draft: '', cloud: true }])
      }
      const result = await listMessages(id)
      if (owner.current !== user) return
      setChats(current => current.map(c => c.id === id ? { ...c, loaded: true, more: result.messages.length === 50, messages: result.messages.map(m => ({ id: m.id, text: m.content, role: m.role })) } : c))
    } catch { if (owner.current === user) setSyncError('Could not load this conversation. Please retry.') }
  }

  async function loadMoreMessages() {
    const user = owner.current, id = chat.id
    try {
      const result = await listMessages(id, chat.messages.length)
      if (owner.current !== user) return
      setChats(current => current.map(c => c.id === id ? { ...c, more: result.messages.length === 50, messages: [...c.messages, ...result.messages.filter(m => !c.messages.some(existing => existing.id === m.id)).map(m => ({ id: m.id, text: m.content, role: m.role }))] } : c))
    } catch { setSyncError('Could not load more messages.') }
  }

  async function retrySync() {
    setSyncError(null)
    if (!isNativeIOS) return
    const snapshot = await NativeChatControls.accountState()
    if (snapshot.state !== 'signedIn') { setSyncError('Your account is still offline. Please try again when connected.'); return }
    const user = owner.current
    try {
      const result = await listChats()
      if (owner.current !== user) return
      setChats(current => [...current, ...result.chats.filter(c => !current.some(existing => existing.id === c.id)).map(c => ({ ...c, messages: [], draft: '', cloud: true }))])
      await selectChat(chat.id)
    } catch { setSyncError('Could not sync your account. Please try again.') }
  }

  useLayoutEffect(() => {
    if (input.current) {
      input.current.style.height = '0px'
      input.current.style.height = `${Math.min(input.current.scrollHeight, 144)}px`
    }
  }, [chat.draft, chat.id])

  useLayoutEffect(() => {
    const area = conversation.current
    if (area) area.scrollTop = area.scrollHeight
  }, [chat.messages.length, chat.id])

  function newChat() {
    const empty = chats.find((item) => !item.messages.length && !item.draft)
    const next = empty ?? createChat()
    if (!empty) setChats((current) => [...current, next])
    setActiveId(next.id)
    setPanel(null)
    setAttachmentNotice(null)
    input.current?.blur()
  }

  async function sendText(id: string, text: string) {
    if (!text.trim() || sending.current) return
    if (isNativeIOS && (accountStatus !== 'signedIn' || !owner.current)) {
      setSyncError(accountStatus === 'offline' ? 'You are offline. Your session is saved; reconnect to send.' : 'Sign in from Settings to save your conversations.')
      setChats(current => current.map(c => c.id === id ? { ...c, draft: text } : c)); return
    }
    const selected = chats.find(c => c.id === id)
    if (!selected) return
    if (selected.cloud && !selected.loaded) { setSyncError('Please wait for this conversation to load before sending.'); return }
    if (!isNativeIOS) {
      setChats(current => current.map(c => c.id === id ? { ...c, draft: '', messages: [...c.messages, { id: crypto.randomUUID(), text }] } : c)); return
    }
    sending.current = true; setSyncing(true); setSyncError(null)
    const user = owner.current
    let target = id
    try {
      if (!selected.cloud) {
        const result = await accountRequest<{ chat: CloudChat }>('POST', '/chats', { id })
        if (owner.current !== user) return
        target = result.chat.id
        setChats(current => current.map(c => c.id === id ? { ...c, id: target, cloud: true, loaded: true } : c))
        setActiveId(target)
      }
      if (pendingMessage.current?.chatId !== target || pendingMessage.current.text !== text.trim()) pendingMessage.current = { chatId: target, text: text.trim(), id: crypto.randomUUID() }
      const result = await accountRequest<{ message: CloudMessage }>('POST', `/chats/${target}/messages`, { id: pendingMessage.current.id, content: text.trim() })
      if (owner.current !== user) return
      pendingMessage.current = null
      setChats(current => current.map(c => c.id === target ? { ...c, draft: '', title: c.title || text.trim().replace(/\s+/g, ' ').slice(0, 80), messages: [...c.messages.filter(m => m.id !== result.message.id), { id: result.message.id, text: result.message.content, role: result.message.role }] } : c))
    } catch {
      if (owner.current === user) {
        setChats(current => current.map(c => c.id === target ? { ...c, draft: text } : c))
        setSyncError('Message could not be confirmed saved. Reload the conversation before retrying.')
      }
    } finally { sending.current = false; setSyncing(false) }
  }
  function send() { if (canSend) void sendText(chat.id, chat.draft) }

  function openPanel(next: Panel) {
    input.current?.blur()
    setPanel(next)
  }

  return (
    <main className={`chat-app${isNativeIOS ? ' native-chat' : ''}`} aria-label="ChatPop" style={isNativeIOS ? {
      '--native-top': `${native.insets.top}px`, '--native-bottom': `${native.insets.bottom}px`,
    } as CSSProperties : undefined}>
      {isNativeIOS && native.error && <div className="native-error" role="alert">
        <p>Chat controls unavailable</p>
        <button onClick={native.retry}>Retry</button>
      </div>}
      {!isNativeIOS && <header className="top-bar">
        <button className="icon-button" aria-label="Open menu" title="Menu" aria-haspopup="dialog" aria-expanded={panel === 'menu'} onClick={() => openPanel('menu')}>
          <Menu size={23} />
        </button>
        <button ref={modelTrigger} className="model-trigger" aria-label={`Select AI model, current: ${model}`} aria-haspopup="dialog" aria-expanded={panel === 'models'} onClick={() => openPanel('models')}>
          {model === 'Auto' && <Sparkles size={16} className="accent" />}
          <span>{model}</span><ChevronDown size={15} className="muted" />
        </button>
        <button className="icon-button" aria-label="New chat" title="New chat" onClick={newChat}>
          <SquarePen size={22} />
        </button>
      </header>}

      <div className="conversation" ref={conversation}>
        {syncError && <div role="alert"><p>{syncError}</p><button onClick={() => void retrySync()}>Retry</button></div>}
        {syncing && <p role="status">Saving message...</p>}
        {chat.messages.length === 0 ? (
          <div className="empty-state">
            <BrandMark size={88} className="empty-brand" decorative />
            <h1>ChatPop<span className="brand-dot">.</span></h1>
            <p>What's on your mind?</p>
          </div>
        ) : (
          <div className="message-list" role="log" aria-label="Conversation" aria-live="polite" aria-relevant="additions">
            {chat.messages.map((message) => (
              <article className="message" key={message.id} aria-label={message.role === 'assistant' ? 'Assistant message' : 'Your message'}>
                <p dir="auto">{message.text}</p>
                <span className="message-status">{chat.cloud ? 'Saved' : 'Local only'}</span>
              </article>
            ))}
            {chat.more && <button onClick={() => void loadMoreMessages()}>Load more messages</button>}
          </div>
        )}
      </div>

      {!isNativeIOS && <div className="composer-dock">
        {attachmentNotice && (
          <div className="attachment-notice" role="status">
            <span>{attachmentNotice} attachments are not connected yet.</span>
            <button className="icon-button" aria-label="Dismiss attachment notice" title="Dismiss" onClick={() => setAttachmentNotice(null)}><X size={16} /></button>
          </div>
        )}
        <form className="composer" onSubmit={(event) => { event.preventDefault(); if (canSend) send(); else openPanel('microphone') }}>
          <textarea
            ref={input}
            rows={1}
            value={chat.draft}
            aria-label="Message ChatPop"
            placeholder="Message ChatPop..."
            onChange={(event) => setChats((current) => current.map((item) => item.id === chat.id ? { ...item, draft: event.target.value } : item))}
            onKeyDown={(event) => {
              if (event.key === 'Enter' && !event.shiftKey && !event.nativeEvent.isComposing && matchMedia('(pointer: fine)').matches) {
                event.preventDefault()
                send()
              }
            }}
          />
          <div className="composer-actions">
            <button ref={attachmentTrigger} type="button" className="icon-button attachment-button" aria-label="Add attachment" title="Add attachment" aria-haspopup="dialog" aria-expanded={panel === 'attachments'} onClick={() => openPanel('attachments')}><Plus size={23} /></button>
            <div className="send-actions">
              <button type="button" className="icon-button" aria-label="Open voice" title="Voice" aria-haspopup="dialog" onClick={() => openPanel('microphone')}><Mic size={21} /></button>
              <button className="icon-button send-button" type="submit" aria-label={canSend ? 'Send message' : 'Open voice mode'} title={canSend ? 'Send message' : 'Voice mode'} aria-haspopup={canSend ? undefined : 'dialog'} onPointerDown={(event) => { if (canSend) event.preventDefault() }}>
                {canSend ? <ArrowUp size={23} strokeWidth={2.4} /> : <AudioLines size={23} strokeWidth={2.2} />}
              </button>
            </div>
          </div>
        </form>
      </div>}

      {panel === 'menu' && (
        <ChatDrawer
          chats={chats.map((item) => ({ id: item.id, title: item.title ?? item.messages[0]?.text ?? (item.draft || 'New chat') }))}
          activeId={chat.id}
          onSelect={(id) => { void selectChat(id) }}
          onNewChat={newChat}
          onClose={() => setPanel(null)}
        />
      )}
      {!isNativeIOS && panel === 'models' && <ModelPanel anchor={modelTrigger} selected={model} onSelect={setModel} onClose={() => setPanel(null)} />}
      {!isNativeIOS && panel === 'microphone' && <VoiceModal onClose={() => setPanel(null)} />}
      {!isNativeIOS && panel === 'attachments' && <AttachmentMenu anchor={attachmentTrigger} onSelect={setAttachmentNotice} onClose={() => setPanel(null)} />}
    </main>
  )
}
