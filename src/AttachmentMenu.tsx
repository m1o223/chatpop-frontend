import { useEffect, useId, useLayoutEffect, useRef, useState } from 'react'
import type { CSSProperties, RefObject } from 'react'
import { AudioLines, Camera, File, Image, X } from 'lucide-react'
import './AttachmentMenu.css'

const actions = [
  { name: 'Camera', icon: Camera, color: 'camera' },
  { name: 'Photos', icon: Image, color: 'photos' },
  { name: 'Audio', icon: AudioLines, color: 'audio' },
  { name: 'File', icon: File, color: 'file' },
] as const

type Props = {
  anchor: RefObject<HTMLButtonElement | null>
  onSelect: (action: string) => void
  onClose: () => void
}

export function AttachmentMenu({ anchor, onSelect, onClose }: Props) {
  const dialog = useRef<HTMLDialogElement>(null)
  const selection = useRef<string | null>(null)
  const [closing, setClosing] = useState(false)
  const titleId = useId()

  useLayoutEffect(() => {
    let frame = 0
    const position = () => {
      const element = dialog.current
      const button = anchor.current
      if (!element || !button) return
      const rect = button.getBoundingClientRect()
      const viewport = window.visualViewport
      const top = viewport?.offsetTop ?? 0
      const height = viewport?.height ?? window.innerHeight
      const width = viewport?.width ?? window.innerWidth
      const bottom = Math.min(rect.bottom, top + height - 12)
      const left = Math.max(12, Math.min(rect.left, width - 180))
      element.style.setProperty('--attachment-left', `${left}px`)
      element.style.setProperty('--attachment-bottom', `${bottom}px`)
      element.style.setProperty('--attachment-width', `${Math.min(272, width - left - 16)}px`)
      element.style.setProperty('--attachment-height', `${Math.max(80, bottom - top - 12)}px`)
    }
    const schedule = () => {
      cancelAnimationFrame(frame)
      frame = requestAnimationFrame(position)
    }
    position()
    const observer = new ResizeObserver(schedule)
    if (anchor.current) {
      observer.observe(anchor.current)
      const composer = anchor.current.closest('.composer')
      if (composer) observer.observe(composer)
    }
    window.addEventListener('resize', schedule)
    window.visualViewport?.addEventListener('resize', schedule)
    window.visualViewport?.addEventListener('scroll', schedule)
    return () => {
      cancelAnimationFrame(frame)
      observer.disconnect()
      window.removeEventListener('resize', schedule)
      window.visualViewport?.removeEventListener('resize', schedule)
      window.visualViewport?.removeEventListener('scroll', schedule)
    }
  }, [anchor])

  useEffect(() => {
    const element = dialog.current
    const trigger = anchor.current
    element?.showModal()
    element?.querySelector<HTMLButtonElement>('.attachment-menu-close')?.focus({ preventScroll: true })
    return () => {
      element?.close()
      if (trigger?.isConnected) trigger.focus({ preventScroll: true })
    }
  }, [anchor])

  useEffect(() => {
    if (!closing) return
    const timer = window.setTimeout(() => {
      if (selection.current) onSelect(selection.current)
      onClose()
    }, matchMedia('(prefers-reduced-motion: reduce)').matches ? 0 : 310)
    return () => window.clearTimeout(timer)
  }, [closing, onClose, onSelect])

  function close(action?: string) {
    if (closing) return
    // Reverse from the current presentation when a tap interrupts the entrance.
    const element = dialog.current
    element?.querySelectorAll<HTMLButtonElement>('button').forEach((button) => {
      const current = getComputedStyle(button)
      button.style.setProperty('--exit-transform', current.transform)
      button.style.setProperty('--exit-opacity', current.opacity)
    })
    if (element) element.style.setProperty('--scrim-exit-opacity', getComputedStyle(element, '::backdrop').opacity)
    selection.current = action ?? null
    setClosing(true)
  }

  return (
    <dialog ref={dialog} className={`attachment-menu${closing ? ' is-closing' : ''}`} aria-labelledby={titleId}
      onCancel={(event) => { event.preventDefault(); close() }}
      onClick={(event) => { if (event.target === event.currentTarget) close() }}
      onKeyDown={(event) => {
        if (event.key !== 'Tab') return
        if (closing) { event.preventDefault(); return }
        const buttons = event.currentTarget.querySelectorAll<HTMLButtonElement>('button:not(:disabled)')
        const first = buttons[0]
        const last = buttons[buttons.length - 1]
        if (event.shiftKey && document.activeElement === first) {
          event.preventDefault()
          last?.focus()
        } else if (!event.shiftKey && document.activeElement === last) {
          event.preventDefault()
          first?.focus()
        }
      }}>
      <h2 id={titleId} className="attachment-menu-title">Add attachment</h2>
      <div className="attachment-menu-stack">
        <div className="attachment-menu-actions">
          {actions.map(({ name, icon: Icon, color }, index) => (
            <button key={name} className="attachment-quick-action" disabled={closing} onClick={() => close(name)}
              style={{ '--action-index': index, '--action-distance': `${(4 - index) * 66}px` } as CSSProperties}>
              <span className={`attachment-quick-icon ${color}`} aria-hidden="true"><Icon size={24} strokeWidth={1.9} /></span>
              <span>{name}</span>
            </button>
          ))}
        </div>
        <button className="attachment-menu-close" aria-label="Close attachment menu" title="Close attachment menu"
          disabled={closing} onClick={() => close()}><X size={23} /></button>
      </div>
    </dialog>
  )
}
