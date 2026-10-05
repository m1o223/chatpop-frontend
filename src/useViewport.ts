import { useEffect } from 'react'

export function useViewport() {
  useEffect(() => {
    const viewport = window.visualViewport
    const root = document.documentElement
    let frame = 0
    const update = () => {
      // Follow the visible WKWebView area when the keyboard resizes or pans it.
      if (viewport && viewport.scale !== 1) return
      root.style.setProperty('--viewport-height', `${viewport?.height ?? window.innerHeight}px`)
      root.style.setProperty('--viewport-top', `${viewport?.offsetTop ?? 0}px`)
      root.classList.toggle('keyboard-open', window.innerHeight - (viewport?.height ?? window.innerHeight) > 120)
    }
    const schedule = () => {
      cancelAnimationFrame(frame)
      frame = requestAnimationFrame(update)
    }
    update()
    viewport?.addEventListener('resize', schedule)
    viewport?.addEventListener('scroll', schedule)
    window.addEventListener('resize', schedule)
    return () => {
      cancelAnimationFrame(frame)
      viewport?.removeEventListener('resize', schedule)
      viewport?.removeEventListener('scroll', schedule)
      window.removeEventListener('resize', schedule)
      root.style.removeProperty('--viewport-height')
      root.style.removeProperty('--viewport-top')
      root.classList.remove('keyboard-open')
    }
  }, [])
}
