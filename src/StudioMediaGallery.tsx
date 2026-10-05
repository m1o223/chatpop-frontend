import { useEffect, useRef, useState, type CSSProperties } from 'react'

const mediaRoot = '/media/creative/'

export type CreativeMediaItem = {
  id: string
  type: 'image' | 'video'
  source: string
  poster?: string
  aspectRatio: number
  altText: string
  columnSpan: 1 | 2
}

type GalleryManifest = { cycleDuration: number; items: CreativeMediaItem[] }
type PositionedMedia = CreativeMediaItem & { x: number; y: number; width: number; height: number }

const fallback: GalleryManifest = {
  cycleDuration: 40,
  items: [
    { id: 'coast', type: 'image', source: 'coast.jpg', aspectRatio: 1.4, altText: 'Cinematic coastal environment', columnSpan: 2 },
    { id: 'portrait', type: 'image', source: 'portrait.jpg', aspectRatio: 0.75, altText: 'Original cinematic character', columnSpan: 1 },
    { id: 'architecture', type: 'image', source: 'architecture.jpg', aspectRatio: 0.75, altText: 'Creative architecture', columnSpan: 1 },
    { id: 'landscape', type: 'image', source: 'landscape.jpg', aspectRatio: 1.5, altText: 'Imagined landscape', columnSpan: 2 },
  ],
}

let manifestPromise: Promise<GalleryManifest> | undefined

function loadManifest(): Promise<GalleryManifest> {
  manifestPromise ??= fetch(`${mediaRoot}gallery.json`)
    .then(async (response) => {
      if (!response.ok) throw new Error('Unavailable gallery')
      const manifest: unknown = await response.json()
      if (!validManifest(manifest)) throw new Error('Invalid gallery')
      return manifest
    })
    .catch(() => fallback)
  return manifestPromise
}

function validManifest(value: unknown): value is GalleryManifest {
  if (!value || typeof value !== 'object') return false
  const manifest = value as Partial<GalleryManifest>
  if (typeof manifest.cycleDuration !== 'number' || manifest.cycleDuration < 12 || manifest.cycleDuration > 120 || !Array.isArray(manifest.items) || manifest.items.length < 4 || manifest.items.length > 24) return false
  const ids = new Set<string>()
  let videoCount = 0
  return manifest.items.every((item) => {
    if (!item || typeof item !== 'object' || typeof item.id !== 'string' || ids.has(item.id)) return false
    ids.add(item.id)
    if (item.type !== 'image' && item.type !== 'video') return false
    if (typeof item.source !== 'string' || !/^[a-zA-Z0-9_-]+\.(jpg|jpeg|png|webp|mp4)$/.test(item.source)) return false
    if (item.type === 'video' && (++videoCount > 1 || typeof item.poster !== 'string' || !/^[a-zA-Z0-9_-]+\.(jpg|jpeg|png|webp)$/.test(item.poster))) return false
    return typeof item.altText === 'string' && typeof item.aspectRatio === 'number' && item.aspectRatio >= 0.5 && item.aspectRatio <= 3 && (item.columnSpan === 1 || item.columnSpan === 2)
  })
}

// Coordinates are normalized to the gallery width, so rotations need no per-frame layout work.
function positionMedia(items: CreativeMediaItem[]) {
  const gap = 0.018
  const columnWidth = (1 - gap) / 2
  const bottoms = [0, 0]
  const tiles: PositionedMedia[] = items.map((item) => {
    const column = bottoms[0] <= bottoms[1] ? 0 : 1
    const wide = item.columnSpan === 2
    const width = wide ? 1 : columnWidth
    const height = width / item.aspectRatio
    const y = wide ? Math.max(...bottoms) : bottoms[column]
    if (wide) bottoms.fill(y + height + gap)
    else bottoms[column] = y + height + gap
    return { ...item, x: wide ? 0 : column * (columnWidth + gap), y, width, height }
  })
  return { tiles, height: Math.max(...bottoms) }
}

export function StudioMediaGallery({ playing }: { playing: boolean }) {
  const gallery = useRef<HTMLSpanElement>(null)
  const track = useRef<HTMLSpanElement>(null)
  const player = useRef<{ setPlaying: (playing: boolean) => void } | null>(null)
  const [manifest, setManifest] = useState<GalleryManifest>(fallback)
  const layout = positionMedia(manifest.items)

  useEffect(() => {
    let mounted = true
    void loadManifest().then((value) => { if (mounted) setManifest(value) })
    return () => { mounted = false }
  }, [])

  useEffect(() => {
    const root = gallery.current
    const item = manifest.items.find((media) => media.type === 'video')
    if (!root || !item) return
    const slots = [...root.querySelectorAll<HTMLElement>('[data-video-slot]')]
    const video = document.createElement('video')
    video.className = 'studio-gallery-video'
    video.muted = true
    video.defaultMuted = true
    video.loop = true
    video.playsInline = true
    video.controls = false
    video.preload = 'none'
    video.tabIndex = -1
    video.setAttribute('aria-hidden', 'true')
    video.setAttribute('disablepictureinpicture', '')
    video.poster = `${mediaRoot}${item.poster}`
    video.src = `${mediaRoot}${item.source}`
    const visible = new Map<Element, number>()
    let active = false
    let disposed = false
    const updatePlayback = () => {
      const slot = slots.find((candidate) => (visible.get(candidate) ?? 0) > 0)
      if (!active || !slot) {
        video.pause()
        return
      }
      // Reparent the same player between duplicated poster slots; never create a second decoder.
      if (video.parentElement !== slot) slot.append(video)
      if (video.paused) void video.play().catch(() => { video.dataset.ready = 'false' })
    }
    const ready = () => { if (!disposed) video.dataset.ready = 'true' }
    const unavailable = () => { video.dataset.ready = 'false' }
    video.addEventListener('playing', ready)
    video.addEventListener('error', unavailable)
    const observer = new IntersectionObserver((entries) => {
      entries.forEach((entry) => visible.set(entry.target, entry.isIntersecting ? entry.intersectionRatio : 0))
      updatePlayback()
    }, { root, threshold: [0, 0.01] })
    slots.forEach((slot) => observer.observe(slot))
    player.current = { setPlaying: (value) => { active = value; updatePlayback() } }
    return () => {
      disposed = true
      observer.disconnect()
      player.current = null
      video.pause()
      video.removeEventListener('playing', ready)
      video.removeEventListener('error', unavailable)
      video.removeAttribute('src')
      video.load()
      video.remove()
    }
  }, [manifest])

  useEffect(() => { player.current?.setPlaying(playing) }, [playing, manifest])

  useEffect(() => {
    const preference = window.matchMedia('(prefers-reduced-motion: reduce)')
    const updateMotion = () => {
      const animation = track.current?.getAnimations()[0]
      // Changing playback rate retains the current position when accessibility settings change.
      animation?.updatePlaybackRate(preference.matches ? manifest.cycleDuration / 100 : 1)
    }
    updateMotion()
    preference.addEventListener('change', updateMotion)
    return () => preference.removeEventListener('change', updateMotion)
  }, [manifest.cycleDuration])

  const styles = {
    '--studio-cycle-duration': `${manifest.cycleDuration}s`,
  } as CSSProperties

  return <span ref={gallery} className="studio-collage" aria-hidden="true" style={styles}>
    <span ref={track} className="studio-gallery-track">
      {[0, 1].map((copy) => <span key={copy} className="studio-gallery-cycle" style={{ aspectRatio: `1 / ${layout.height}` }}>
        {layout.tiles.map((item) => <span
          key={item.id}
          className="studio-media-tile"
          data-media-id={item.id}
          data-media-type={item.type}
          data-video-slot={item.type === 'video' ? copy : undefined}
          style={{ left: `${item.x * 100}%`, top: `${item.y / layout.height * 100}%`, width: `${item.width * 100}%`, height: `${item.height / layout.height * 100}%` }}
        >
          <img src={`${mediaRoot}${item.type === 'video' ? item.poster : item.source}`} alt="" decoding="async" draggable={false} onError={(event) => { event.currentTarget.style.opacity = '0' }} />
        </span>)}
      </span>)}
    </span>
  </span>
}
