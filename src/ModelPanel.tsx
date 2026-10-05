import { useEffect, useId, useLayoutEffect, useRef, useState } from 'react'
import type { RefObject } from 'react'
import { Check, Sparkles, X } from 'lucide-react'
import { modelSections } from './models'
import type { Model } from './models'
import './ModelPanel.css'

type Props = {
  anchor: RefObject<HTMLButtonElement | null>
  selected: Model
  onSelect: (model: Model) => void
  onClose: () => void
}

export function ModelPanel({ anchor, selected, onSelect, onClose }: Props) {
  const dialog = useRef<HTMLDialogElement>(null)
  const [closing, setClosing] = useState(false)
  const titleId = useId()

  useLayoutEffect(() => {
    const position = () => {
      const element = dialog.current
      const button = anchor.current
      if (!element || !button) return
      const rect = button.getBoundingClientRect()
      const viewport = window.visualViewport
      const bottom = (viewport?.offsetTop ?? 0) + (viewport?.height ?? window.innerHeight)
      element.style.top = `${rect.bottom + 8}px`
      element.style.setProperty('--panel-available-height', `${Math.max(0, bottom - rect.bottom - 20)}px`)
    }
    position()
    const observer = new ResizeObserver(position)
    if (anchor.current) observer.observe(anchor.current)
    window.addEventListener('resize', position)
    window.visualViewport?.addEventListener('resize', position)
    window.visualViewport?.addEventListener('scroll', position)
    return () => {
      observer.disconnect()
      window.removeEventListener('resize', position)
      window.visualViewport?.removeEventListener('resize', position)
      window.visualViewport?.removeEventListener('scroll', position)
    }
  }, [anchor])

  useEffect(() => {
    const element = dialog.current
    const previousFocus = document.activeElement
    element?.showModal()
    return () => {
      element?.close()
      if (previousFocus instanceof HTMLElement) previousFocus.focus({ preventScroll: true })
    }
  }, [])

  useEffect(() => {
    if (!closing) return
    const timer = window.setTimeout(onClose,
      matchMedia('(prefers-reduced-motion: reduce)').matches ? 0 : 200)
    return () => window.clearTimeout(timer)
  }, [closing, onClose])

  return (
    <dialog ref={dialog} className={`model-panel${closing ? ' is-closing' : ''}`} aria-labelledby={titleId}
      onCancel={(event) => { event.preventDefault(); setClosing(true) }}
      onClick={(event) => {
        if (event.target !== event.currentTarget) return
        const rect = event.currentTarget.getBoundingClientRect()
        if (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom) setClosing(true)
      }}>
      <header className="model-panel-header">
        <h2 id={titleId}>Choose a model</h2>
        <button className="icon-button" aria-label="Close model panel" title="Close" onClick={() => setClosing(true)}><X size={20} /></button>
      </header>
      <div className="provider-list" role="group" aria-label="AI models">
        {modelSections.map((section) => (
          <section key={section.title} className="model-section" aria-label={section.title}>
          <h3>{section.title}</h3>
          {section.models.map((provider) => (
          <button key={provider.name} className="provider-option" aria-pressed={selected === provider.name}
            disabled={closing}
            onClick={() => { onSelect(provider.name); setClosing(true) }}>
            <span className="provider-symbol" aria-hidden="true">{provider.symbol ?? <Sparkles size={20} />}</span>
            <span className="provider-copy"><span className="provider-name">{provider.label}</span>{provider.name === 'Auto' && <span className="provider-description">{provider.description}</span>}</span>
            <span className="provider-check" aria-hidden="true">{selected === provider.name && <Check size={19} />}</span>
          </button>
          ))}
          </section>
        ))}
      </div>
    </dialog>
  )
}
