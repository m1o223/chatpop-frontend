import { useEffect, useId, useLayoutEffect, useRef, useState } from 'react'
import { StudioMediaGallery } from './StudioMediaGallery'
import { ArrowUpRight, X } from 'lucide-react'
import './CreativeStudioCard.css'

const mediaRoot = '/media/creative/'

type StudioCardProps = { paused?: boolean }

export function CreativeStudioCard({ paused = false }: StudioCardProps) {
  const card = useRef<HTMLButtonElement>(null)
  const [showStudio, setShowStudio] = useState(false)
  const [visible, setVisible] = useState(false)
  const [interacting, setInteracting] = useState(false)
  const playing = visible && !paused && !showStudio && !interacting

  useEffect(() => {
    const element = card.current
    if (!element) return
    let inViewport = false
    const updatePlayback = () => {
      setVisible(inViewport && !document.hidden)
    }
    const observer = new IntersectionObserver(([entry]) => {
      inViewport = Boolean(entry?.isIntersecting)
      updatePlayback()
    }, { threshold: 0.1 })
    observer.observe(element)
    document.addEventListener('visibilitychange', updatePlayback)
    updatePlayback()
    return () => {
      observer.disconnect()
      document.removeEventListener('visibilitychange', updatePlayback)
    }
  }, [])

  useEffect(() => {
    if (!interacting) return
    let resume: number | undefined
    const endInteraction = () => {
      window.clearTimeout(resume)
      resume = window.setTimeout(() => setInteracting(false), 250)
    }
    window.addEventListener('pointerup', endInteraction)
    window.addEventListener('pointercancel', endInteraction)
    window.addEventListener('blur', endInteraction)
    return () => {
      window.clearTimeout(resume)
      window.removeEventListener('pointerup', endInteraction)
      window.removeEventListener('pointercancel', endInteraction)
      window.removeEventListener('blur', endInteraction)
    }
  }, [interacting])

  return <>
    <button
      ref={card}
      type="button"
      className="creative-studio-card"
      data-playing={playing}
      aria-label="Creative Studio. Create images and videos. Try it."
      aria-haspopup="dialog"
      onClick={() => setShowStudio(true)}
      onPointerDown={() => setInteracting(true)}
    >
      <StudioMediaGallery playing={playing} />
      <span className="studio-card-shade" aria-hidden="true" />
      <span className="studio-card-copy">
        <span className="studio-card-eyebrow">Create Images &amp; Videos with AI</span>
        <span className="studio-card-title">Creative<br />Studio</span>
      </span>
      <span className="studio-card-cta" aria-hidden="true">Try it <ArrowUpRight size={17} /></span>
    </button>
    {showStudio && <CreativeStudioScreen onClose={() => setShowStudio(false)} />}
  </>
}

function CreativeStudioScreen({ onClose }: { onClose: () => void }) {
  const dialog = useRef<HTMLDialogElement>(null)
  const animation = useRef<Animation | null>(null)
  const closeStarted = useRef(false)
  const titleId = useId()
  const [closing, setClosing] = useState(false)

  useLayoutEffect(() => {
    const element = dialog.current
    if (!element) return
    const previousFocus = document.activeElement
    closeStarted.current = false
    element.style.opacity = '0'
    element.style.transform = studioDismissedTransform()
    element.showModal()
    const opening = element.animate([
      { transform: studioDismissedTransform(), opacity: 0 },
      { transform: 'none', opacity: 1 },
    ], studioTransition())
    animation.current = opening
    opening.onfinish = () => {
      if (animation.current !== opening) return
      element.style.opacity = '1'
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

  function close() {
    const element = dialog.current
    if (!element || closeStarted.current) return
    closeStarted.current = true
    setClosing(true)
    const computed = getComputedStyle(element)
    const transform = computed.transform
    const opacity = computed.opacity
    element.style.transform = transform
    element.style.opacity = opacity
    animation.current?.cancel()
    const exiting = element.animate([
      { transform, opacity },
      { transform: studioDismissedTransform(), opacity: 0 },
    ], studioTransition())
    animation.current = exiting
    exiting.onfinish = () => {
      if (animation.current === exiting) onClose()
    }
  }

  return <dialog
    ref={dialog}
    className={`creative-studio-screen${closing ? ' is-closing' : ''}`}
    aria-labelledby={titleId}
    onCancel={(event) => { event.preventDefault(); event.stopPropagation(); close() }}
  >
    <header className="studio-screen-header">
      <h2 id={titleId}>Creative Studio</h2>
      <button type="button" className="icon-button" aria-label="Close Creative Studio" title="Close Creative Studio" onClick={close}><X size={21} /></button>
    </header>
    <div className="studio-screen-content">
      <img className="studio-screen-preview" src={`${mediaRoot}coast.jpg`} alt="A cinematic coastal landscape" decoding="async" />
      <p>Image and video creation is not available yet.</p>
    </div>
  </dialog>
}

function studioTransition(): KeyframeAnimationOptions {
  return {
    duration: window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 180 : 360,
    easing: 'cubic-bezier(0.22, 1, 0.36, 1)',
    fill: 'both',
  }
}

function studioDismissedTransform(): string {
  return window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 'none' : 'translateY(30px) scale(0.975)'
}
