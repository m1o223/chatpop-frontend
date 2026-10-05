import { useEffect, useId, useRef, useState } from 'react'
import { BarChart3, Bolt, Eye, FileText, Folder, Globe, Image, Layers, Mic, Sparkles, Video, Waves, X } from 'lucide-react'
import type { LucideIcon } from 'lucide-react'
import { BrandMark } from './BrandMark'
import source from '../public/subscription/plans.json'
import './PaywallScreen.css'

type Status = 'available' | 'comingSoon' | 'disabled'
type Provider = { id: string; name: string; status: Status }
type Feature = { id: string; title: string; description: string; symbol: string; status: Status }
type Plan = { id: string; name: string; description: string; badge: string; models: string[]; features: string[]; creativeCredits: number | null; usageLevel: string; monthlyPrice: string | null; yearlyPrice: string | null }
const catalog = source as { providers: Provider[]; plans: Plan[]; sections: { title: string; columns: boolean; features: Feature[] }[] }
const icons: Record<string, LucideIcon> = { photo: Image, video: Video, waveform: Waves, mic: Mic, folder: Folder, 'doc.text': FileText, eye: Eye, globe: Globe, 'square.stack': Layers, sparkles: Sparkles }
const availability = (included: boolean, status: Status) => !included ? 'Pro · Coming soon' : status === 'available' ? 'Available in app' : 'Coming soon'

function Benefit({ title, detail, status, icon: Icon }: { title: string; detail?: string; status: string; icon: LucideIcon }) {
  return <article className="subscription-benefit"><Icon size={22} aria-hidden="true" /><div><h4>{title}</h4>{detail && <p>{detail}</p>}<small>{status}</small></div></article>
}

export function PaywallScreen({ onClose }: { onClose: () => void }) {
  const [planId, setPlanId] = useState('plus')
  const [yearly, setYearly] = useState(false)
  const [notice, setNotice] = useState<{ title: string; message: string } | null>(null)
  const dialog = useRef<HTMLDialogElement>(null)
  const noticeDialog = useRef<HTMLDialogElement>(null)
  const titleId = useId()
  const plan = catalog.plans.find((item) => item.id === planId) ?? catalog.plans[0]!
  const price = (yearly ? plan.yearlyPrice : plan.monthlyPrice) ?? 'Coming soon'
  useEffect(() => {
    const previous = document.activeElement
    const element = dialog.current
    element?.showModal()
    return () => { element?.close(); if (previous instanceof HTMLElement) previous.focus({ preventScroll: true }) }
  }, [])
  useEffect(() => {
    if (!notice) return
    const previous = document.activeElement
    const element = noticeDialog.current
    element?.showModal()
    return () => { element?.close(); if (previous instanceof HTMLElement) previous.focus({ preventScroll: true }) }
  }, [notice])
  return <dialog ref={dialog} className="subscription-screen" aria-labelledby={titleId} onCancel={(event) => { event.preventDefault(); onClose() }}>
    <header className="subscription-header"><h2 id={titleId}>ChatPop Plus / Pro</h2><button aria-label="Close subscription" onClick={onClose}><X size={21} /></button></header>
    <div className="subscription-scroll">
      <div className="subscription-hero"><BrandMark size={96} decorative /><h1>ChatPop Plus / Pro</h1><p>All your AI tools in one app</p></div>
      <div className="subscription-segments" role="group" aria-label="Plan">{catalog.plans.map((item) => <button key={item.id} aria-pressed={planId === item.id} onClick={() => setPlanId(item.id)}>{item.name}</button>)}</div>
      <div className="subscription-summary"><span>{plan.badge}</span><p>{plan.description}</p></div>
      <section className="subscription-models"><h3>AI Models</h3><p>Access leading AI models in one place</p><div className="subscription-providers">{catalog.providers.filter((provider) => provider.status !== 'disabled').map((provider) => <div key={provider.id}><strong>{provider.name}</strong><small>{availability(plan.models.includes(provider.id), provider.status)}</small></div>)}</div></section>
      {catalog.sections.map((section) => <section className="subscription-section" key={section.title}><h3>{section.title}</h3><div className={section.columns ? 'subscription-pair' : 'subscription-rows'}>{section.features.filter((feature) => feature.status !== 'disabled').map((feature) => <Benefit key={feature.id} title={feature.title} detail={feature.description} status={availability(plan.features.includes(feature.id), feature.status)} icon={icons[feature.symbol] ?? Sparkles} />)}</div></section>)}
      <section className="subscription-section"><h3>Usage</h3><div className="subscription-rows">
        <Benefit title="Higher Usage Limits" status={`${plan.usageLevel} · Coming soon`} icon={BarChart3} />
        <Benefit title="Monthly Creative Credits" detail="Credits are used for image and video generation." status={plan.creativeCredits === null ? `${plan.name} allowance announced at launch` : `${plan.creativeCredits.toLocaleString()} credits / month · Coming soon`} icon={Sparkles} />
        <Benefit title="Priority Access" status={plan.features.includes('priority') ? 'Planned for Pro · Coming soon' : 'Pro · Coming soon'} icon={Bolt} />
      </div></section>
    </div>
    <footer className="subscription-dock">
      <div className="subscription-segments" role="group" aria-label="Billing period"><button aria-pressed={!yearly} onClick={() => setYearly(false)}>Monthly</button><button aria-pressed={yearly} onClick={() => setYearly(true)}>Yearly</button></div>
      <div className="subscription-price" aria-live="polite"><span>ChatPop {plan.name}<small>{yearly ? 'Yearly' : 'Monthly'}</small></span><strong>{price}</strong></div>
      <button className="subscription-continue" onClick={() => setNotice({ title: 'ChatPop', message: 'Subscriptions are not available yet. No charge will be made.' })}>Continue with {plan.name}</button>
      <button className="subscription-restore" onClick={() => setNotice({ title: 'Restore Purchases', message: 'App Store restoration is not connected. No purchase was restored.' })}>Restore Purchases</button>
      <div className="subscription-legal">{['Terms of Service', 'Privacy Policy'].map((title) => <button key={title} onClick={() => setNotice({ title, message: 'This page is not published yet.' })}>{title}</button>)}</div>
    </footer>
    {notice && <dialog ref={noticeDialog} className="subscription-notice" aria-label={notice.title} onCancel={(event) => { event.preventDefault(); event.stopPropagation(); setNotice(null) }}><h2>{notice.title}</h2><p>{notice.message}</p><button onClick={() => setNotice(null)}>OK</button></dialog>}
  </dialog>
}
