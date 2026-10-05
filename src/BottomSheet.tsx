import { useEffect, useId, useRef } from 'react'
import type { ReactNode } from 'react'
import { X } from 'lucide-react'

export function BottomSheet({ title, onClose, children }: { title: string; onClose: () => void; children: ReactNode }) {
  const dialog = useRef<HTMLDialogElement>(null)
  const titleId = useId()

  useEffect(() => {
    const element = dialog.current
    element?.showModal()
    return () => element?.close()
  }, [])

  return (
    <dialog ref={dialog} className="bottom-sheet" aria-labelledby={titleId} onCancel={onClose} onClick={(event) => {
      if (event.target !== event.currentTarget) return
      const rect = event.currentTarget.getBoundingClientRect()
      if (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom) onClose()
    }}>
      <div className="sheet-handle" aria-hidden="true" />
      <header className="sheet-header">
        <h2 id={titleId}>{title}</h2>
        <button className="icon-button sheet-close" aria-label="Close panel" title="Close" onClick={onClose}><X size={20} /></button>
      </header>
      {children}
    </dialog>
  )
}
