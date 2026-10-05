import { useEffect, useId, useRef, useState } from 'react'
import type { CSSProperties } from 'react'
import { Mic, MicOff, X } from 'lucide-react'
import { BrandMark } from './BrandMark'
import './VoiceModal.css'

const audioHeights = [10, 18, 27, 38, 51, 67, 83, 96, 105, 109, 103, 91, 77, 66, 71, 84, 93, 86, 72, 55, 40, 29, 20, 13, 8]

export function VoiceModal({ onClose }: { onClose: () => void }) {
  const dialog = useRef<HTMLDialogElement>(null)
  const [muted, setMuted] = useState(false)
  const [closing, setClosing] = useState(false)
  const titleId = useId()

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
      matchMedia('(prefers-reduced-motion: reduce)').matches ? 0 : 220)
    return () => window.clearTimeout(timer)
  }, [closing, onClose])

  return (
    <dialog ref={dialog} className={`voice-modal${muted ? ' is-muted' : ''}${closing ? ' is-closing' : ''}`}
      aria-labelledby={titleId}
      onCancel={(event) => { event.preventDefault(); setClosing(true) }}
      onKeyDown={(event) => {
        if (event.key !== 'Tab') return
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
      <h2 id={titleId} className="voice-visually-hidden">ChatPop voice</h2>
      <div className="voice-modal-header">
        <BrandMark size={32} decorative />
        <button className="voice-control voice-close" aria-label="Close voice" title="Close voice"
          onClick={() => setClosing(true)}><X size={24} /></button>
      </div>
      <div className="voice-orb-stage" aria-hidden="true">
        <div className="voice-orb">
          <div className="voice-audio-lines">
            {audioHeights.map((height, index) => (
              <span key={index} style={{ '--bar-height': `${height}px`, '--bar-delay': `${index * -0.087}s` } as CSSProperties} />
            ))}
          </div>
        </div>
      </div>
      <div className="voice-modal-controls">
        <button className="voice-control voice-microphone" aria-label={muted ? 'Unmute microphone' : 'Mute microphone'}
          title={muted ? 'Unmute microphone' : 'Mute microphone'} aria-pressed={muted}
          disabled={closing} onClick={() => setMuted((current) => !current)}>
          {muted ? <MicOff size={27} /> : <Mic size={27} />}
        </button>
        <span className="voice-visually-hidden" role="status">{muted ? 'Microphone muted' : 'Voice preview. Audio is not being recorded.'}</span>
      </div>
    </dialog>
  )
}
