import { useEffect, useId, useRef, useState } from 'react'
import type { ReactNode } from 'react'
import { Check, ChevronLeft, ChevronRight, Circle, CreditCard, FileText, HelpCircle, Info, MessageCircle, Moon, RotateCcw, Share, Shield, Sparkles, Star, Sun, Trash2, User, Volume2, X } from 'lucide-react'
import { readPreferences, savePreferences, voices } from './preferences'
import type { Preferences } from './preferences'
import './SettingsScreen.css'
import { AuthFlow } from './AuthFlow'
import { BrandMark } from './BrandMark'
import { PaywallScreen } from './PaywallScreen'
export { PaywallScreen } from './PaywallScreen'

const unavailable = (message: string) => window.alert(message)

function Screen({ title, children, onClose, paywall = false, closeVisible = true }: { title: string; children: ReactNode; onClose: () => void; paywall?: boolean; closeVisible?: boolean }) {
  const dialog = useRef<HTMLDialogElement>(null)
  const titleId = useId()
  useEffect(() => {
    const element = dialog.current
    const previousFocus = document.activeElement
    element?.showModal()
    return () => { element?.close(); if (previousFocus instanceof HTMLElement) previousFocus.focus({ preventScroll: true }) }
  }, [])
  return <dialog ref={dialog} className="settings-screen" aria-labelledby={titleId}
    onKeyDown={(event) => { if (event.key === 'Escape') { event.preventDefault(); event.stopPropagation(); onClose() } }}
    onCancel={(event) => { event.preventDefault(); event.stopPropagation(); onClose() }}>
    <header className="settings-header">
      {!paywall && <button className="icon-button" aria-label={`Close ${title}`} onClick={onClose}><ChevronLeft size={22} /></button>}
      <h2 id={titleId}>{title}</h2>
      {paywall && <button className={`icon-button paywall-close${closeVisible ? ' is-visible' : ''}`} aria-label="Close subscription" aria-hidden={!closeVisible} tabIndex={closeVisible ? 0 : -1} onClick={onClose}><X size={22} /></button>}
    </header>
    {children}
  </dialog>
}

function Row({ icon, title, detail, onClick, destructive = false, selected }: { icon: ReactNode; title: string; detail?: string; onClick: () => void; destructive?: boolean; selected?: boolean }) {
  return <button className={`settings-row${destructive ? ' destructive' : ''}`} onClick={onClick} aria-pressed={selected}>
    <span className="settings-row-icon">{icon}</span><span className="settings-row-title">{title}</span>
    {detail && <span className="settings-detail">{detail}</span>}
    {selected === undefined ? <ChevronRight size={16} /> : <span className="settings-check">{selected && <Check size={18} />}</span>}
  </button>
}

function Section({ title, children }: { title: string; children: ReactNode }) {
  return <section className="settings-section"><h3>{title}</h3><div className="settings-group">{children}</div></section>
}

function InfoScreen({ title, onClose }: { title: string; onClose: () => void }) {
  return <Screen title={title} onClose={onClose}><div className="settings-content">{title === 'About ChatPop' && <BrandMark size={72} className="about-brand" decorative />}<p className="settings-secondary">{title === 'About ChatPop' ? 'ChatPop. A place for your conversations.' : 'This page is not published yet.'}</p></div></Screen>
}

export function SettingsScreen({ onClose }: { onClose: () => void }) {
  const [preferences, setPreferences] = useState(readPreferences)
  const [name, setName] = useState(preferences.name)
  const [notice, setNotice] = useState('')
  const [paywall, setPaywall] = useState(false)
  const [auth, setAuth] = useState(false)
  const [info, setInfo] = useState<string | null>(null)
  const nameInput = useRef<HTMLInputElement>(null)
  function update(patch: Partial<Preferences>) {
    const next = { ...preferences, ...patch }
    setPreferences(next)
    setNotice(savePreferences(next) ? 'Saved on this device' : 'Changed for this session. Device storage is unavailable.')
  }
  function editName() { nameInput.current?.scrollIntoView({ block: 'center' }); nameInput.current?.focus() }
  async function share() {
    if (navigator.share) {
      try { await navigator.share({ title: 'ChatPop', text: 'ChatPop' }) } catch (error) {
        if (!(error instanceof DOMException && error.name === 'AbortError')) unavailable('Sharing is unavailable right now.')
      }
    } else setInfo('Share ChatPop')
  }
  return <Screen title="Settings" onClose={onClose}>
    <div className="settings-content">
      <button className="settings-upgrade" onClick={() => setPaywall(true)}><Sparkles size={24} /><span><strong>ChatPop Plus / Pro</strong><small>Explore the next chapter</small></span><ChevronRight size={18} /></button>
      <Section title="Account & Subscription">
        <button className="settings-sign-in" onClick={() => setAuth(true)}><User size={24} /><span><strong>Sign in</strong><small>Sync your account and subscription</small></span></button>
        <Row icon={<User size={20} />} title="Name" detail={preferences.name || 'Not set'} onClick={editName} />
        <Row icon={<CreditCard size={20} />} title="Manage Subscription" onClick={() => unavailable('App Store subscriptions are not connected.')} />
        <Row icon={<RotateCcw size={20} />} title="Restore Purchases" onClick={() => unavailable('Restoration is not connected. No purchase was restored.')} />
        <Row icon={<Trash2 size={20} />} title="Delete Account" destructive onClick={() => { if (window.confirm('No account is connected. This mock action will not delete any data. Continue?')) unavailable('Account deletion is not connected. No data was deleted.') }} />
      </Section>
      <Section title="Voice">{voices.map((voice) => <Row key={voice} icon={<Volume2 size={20} />} title={voice} selected={preferences.voice === voice} onClick={() => update({ voice })} />)}</Section>
      <p className="settings-note">Voice previews are not connected yet.</p>
      <Section title="Appearance">{(['dark', 'light', 'system'] as const).map((theme) => <Row key={theme} icon={theme === 'dark' ? <Moon size={20} /> : theme === 'light' ? <Sun size={20} /> : <SettingsSystemIcon />} title={theme[0]!.toUpperCase() + theme.slice(1)} selected={preferences.theme === theme} onClick={() => update({ theme })} />)}</Section>
      <Section title="Personalisation"><form className="settings-name" onSubmit={(event) => { event.preventDefault(); const trimmed = name.trim(); setName(trimmed); update({ name: trimmed }) }}>
        <label htmlFor="display-name">Your Name</label><input ref={nameInput} id="display-name" placeholder="Display name" autoComplete="nickname" maxLength={60} value={name} onChange={(event) => setName(event.target.value)} /><button type="submit">Save</button>
      </form></Section>
      <Section title="Help & App">
        <Row icon={<HelpCircle size={20} />} title="How to Use ChatPop" onClick={() => setInfo('How to Use ChatPop')} />
        <Row icon={<Info size={20} />} title="About ChatPop" onClick={() => setInfo('About ChatPop')} />
        <Row icon={<MessageCircle size={20} />} title="Feedback & Support" onClick={() => setInfo('Feedback & Support')} />
        <Row icon={<Share size={20} />} title="Share ChatPop" onClick={() => void share()} />
        <Row icon={<Star size={20} />} title="Rate ChatPop" onClick={() => setInfo('Rate ChatPop')} />
      </Section>
      <Section title="Legal"><Row icon={<FileText size={20} />} title="Terms of Service" onClick={() => setInfo('Terms of Service')} /><Row icon={<Shield size={20} />} title="Privacy Policy" onClick={() => setInfo('Privacy Policy')} /></Section>
      <p className="settings-note" role="status">{notice}</p><footer className="settings-version">ChatPop<br />Version 1.0</footer>
    </div>
    {paywall && <PaywallScreen onClose={() => setPaywall(false)} />}
    {auth && <AuthFlow onClose={() => setAuth(false)} />}
    {info && <InfoScreen title={info} onClose={() => setInfo(null)} />}
  </Screen>
}

function SettingsSystemIcon() { return <Circle size={20} /> }
