import './BrandMark.css'

export function BrandMark({ size = 64, decorative = false, className = '' }: {
  size?: number
  decorative?: boolean
  className?: string
}) {
  return <img
    className={`chatpop-brand-mark ${className}`.trim()}
    src="/brand/chatpop-logo.png"
    alt={decorative ? '' : 'ChatPop'}
    width={size}
    height={size}
    decoding="async"
    draggable={false}
  />
}
