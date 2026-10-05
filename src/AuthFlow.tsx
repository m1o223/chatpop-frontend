import { useEffect, useId, useRef, useState } from 'react'
import { ChevronLeft, Eye, EyeOff, X } from 'lucide-react'
import { BrandMark } from './BrandMark'
import './AuthFlow.css'

type Page = 'entry' | 'login' | 'signup' | 'forgot' | 'terms' | 'privacy'
const titles: Record<Page, string> = { entry: 'Log in or sign up', login: 'Log in', signup: 'Create an account', forgot: 'Reset password', terms: 'Terms of Service', privacy: 'Privacy Policy' }
export function AuthFlow({ onClose }: { onClose: () => void }) {
  const dialog = useRef<HTMLDialogElement>(null)
  const heading = useRef<HTMLHeadingElement>(null)
  const [pages, setPages] = useState<Page[]>(['entry'])
  const [agreed, setAgreed] = useState(false)
  const [notice, setNotice] = useState('')
  const titleId = useId()
  const page = pages[pages.length - 1]!
  useEffect(() => {
    const element = dialog.current
    const previous = document.activeElement
    element?.showModal()
    return () => { element?.close(); if (previous instanceof HTMLElement) previous.focus({ preventScroll: true }) }
  }, [])
  useEffect(() => { heading.current?.focus({ preventScroll: true }); dialog.current?.querySelector('.auth-content')?.scrollTo(0, 0) }, [page])
  function back() { setNotice(''); if (pages.length > 1) setPages((current) => current.slice(0, -1)); else onClose() }
  function push(next: Page) { setNotice(''); setPages((current) => [...current, next]) }
  function social(provider: string) {
    setNotice(agreed ? `${provider} sign-in is not connected. No account was created or signed in.` : 'Please review the Terms of Service and Privacy Policy and check the agreement box first.')
  }
  return <dialog ref={dialog} className="auth-screen" aria-labelledby={titleId}
    onCancel={(event) => { event.preventDefault(); event.stopPropagation(); back() }}
    onKeyDown={(event) => { if (event.key === 'Escape') { event.preventDefault(); event.stopPropagation(); back() } }}>
    <header className="auth-header"><button className="icon-button" aria-label="Back" onClick={back}><ChevronLeft size={22} /></button><button className="icon-button" aria-label="Close authentication" onClick={onClose}><X size={22} /></button></header>
    <div className={`auth-content${page === 'login' || page === 'signup' || page === 'forgot' ? ' is-form' : ''}`} onPointerDown={(event) => {
      if (!(event.target as HTMLElement).closest('button,input,a,label') && document.activeElement instanceof HTMLInputElement) document.activeElement.blur()
    }}>
      <div className="auth-brand"><BrandMark size={48} /><h1 id={titleId} ref={heading} tabIndex={-1}>{titles[page]}</h1></div>
      {page === 'entry' ? <>
        <div className="auth-options">
          <button onClick={() => social('Apple')}><span className="auth-apple" aria-hidden="true">{String.fromCodePoint(0xf8ff)}</span><span>Continue with Apple</span></button>
          <button onClick={() => social('Google')}><img src="/auth/google.png" alt="" /><span>Continue with Google</span></button>
          <button onClick={() => social('Microsoft')}><img src="/auth/microsoft.png" alt="" /><span>Continue with Microsoft</span></button>
          <div className="auth-divider"><span />OR<span /></div>
          <button onClick={() => push('login')}>Log in</button><button onClick={() => push('signup')}>Sign up</button>
        </div>
        <div className="auth-consent"><input id="auth-agreement" type="checkbox" checked={agreed} onChange={(event) => { setAgreed(event.target.checked); setNotice('') }} /><div><label htmlFor="auth-agreement">I agree to the </label><button onClick={() => push('terms')}>Terms of Service</button><span> and </span><button onClick={() => push('privacy')}>Privacy Policy</button></div></div>
      </> : page === 'terms' || page === 'privacy' ? <p className="auth-secondary">This document is not published yet. No legal agreement is being submitted in this preview.</p>
        : <AuthForm key={page} page={page} agreed={agreed} onForgot={() => push('forgot')} onNotice={setNotice} />}
      {notice && <p className="auth-notice" role="status">{notice}</p>}
    </div>
  </dialog>
}

function AuthForm({ page, agreed, onForgot, onNotice }: { page: 'login' | 'signup' | 'forgot'; agreed: boolean; onForgot: () => void; onNotice: (message: string) => void }) {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [visible, setVisible] = useState(false)
  const needsPassword = page !== 'forgot'
  const valid = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim()) && (!needsPassword || password.length >= (page === 'signup' ? 8 : 1))
  return <form className="auth-form" onSubmit={(event) => {
    event.preventDefault()
    if (!valid) return
    setPassword(''); setVisible(false)
    if (document.activeElement instanceof HTMLElement) document.activeElement.blur()
    onNotice(page === 'forgot' ? 'Password reset is not connected. No email was sent.' : agreed ? 'Authentication is not connected. No credentials were sent or saved.' : 'Please go back and check the agreement box before continuing.')
  }}>
    {page === 'signup' && <p className="auth-secondary">Set your email and password to continue.</p>}
    {page === 'forgot' && <p className="auth-secondary">Enter your email to request a password reset.</p>}
    <label className="auth-field"><span className="auth-input-label">Email</span><input type="email" inputMode="email" autoCapitalize="none" autoCorrect="off" autoComplete="username" placeholder="Email" value={email} onChange={(event) => setEmail(event.target.value)} required /></label>
    {needsPassword && <label className="auth-field"><span className="auth-input-label">Password</span><input type={visible ? 'text' : 'password'} autoCapitalize="none" autoCorrect="off" autoComplete={page === 'signup' ? 'new-password' : 'current-password'} placeholder="Password" minLength={page === 'signup' ? 8 : 1} value={password} onChange={(event) => setPassword(event.target.value)} required /><button type="button" className="icon-button" aria-label={visible ? 'Hide password' : 'Show password'} aria-pressed={visible} onClick={() => setVisible((value) => !value)}>{visible ? <EyeOff size={20} /> : <Eye size={20} />}</button></label>}
    {page === 'signup' && <p className="auth-secondary auth-password-hint">Use at least 8 characters.</p>}
    {page === 'login' && <button type="button" className="auth-forgot" onClick={onForgot}>Forgot password</button>}
    <div className="auth-submit-dock"><button className="auth-continue" type="submit" disabled={!valid}>Continue</button></div>
  </form>
}
