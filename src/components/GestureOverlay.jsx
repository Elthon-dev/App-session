import { useEffect, useState } from 'react'

export default function GestureOverlay({ overlay, onExpire }) {
  const [visible, setVisible] = useState(false)

  useEffect(() => {
    if (!overlay) return
    setVisible(true)
    const t = setTimeout(() => onExpire?.(), overlay.ttl)
    return () => clearTimeout(t)
  }, [overlay, onExpire])

  if (!overlay) return null

  const style = {
    left: `${overlay.x * 100}%`,
    top: `${overlay.y * 100}%`,
  }

  const angle = overlay.dx && overlay.dy
    ? (Math.atan2(overlay.dy, overlay.dx) * 180) / Math.PI
    : 0

  return (
    <div
      className={`absolute inset-0 pointer-events-none transition-opacity duration-300 ${
        visible ? 'opacity-100' : 'opacity-0'
      }`}
    >
      {overlay.shape === 'swipe' ? (
        <div className="absolute -translate-x-1/2 -translate-y-1/2" style={style}>
          <div className="relative w-20 h-20">
            <div
              className="absolute inset-0 border-[3px] border-green-400 rounded-full animate-pulse shadow-[0_0_20px_rgba(34,197,94,0.35)]"
              style={{ transform: `rotate(${angle}deg)` }}
            />
            <svg
              className="absolute inset-0 w-full h-full"
              viewBox="0 0 100 100"
              style={{ transform: `rotate(${angle}deg)` }}
            >
              <line x1="23" y1="50" x2="68" y2="50" stroke="#4ade80" strokeWidth="6" strokeLinecap="round" />
              <path d="M 58 38 L 72 50 L 58 62" fill="none" stroke="#4ade80" strokeWidth="6" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          </div>
        </div>
      ) : overlay.shape === 'frame' ? (
        <div className="absolute inset-0 border-[6px] border-green-500/80 animate-pulse" style={{ borderRadius: '20px' }} />
      ) : (
        <div className="absolute -translate-x-1/2 -translate-y-1/2" style={style}>
          <div className="w-16 h-16 rounded-full border-4 border-green-400 animate-pulse shadow-[0_0_24px_rgba(34,197,94,0.4)]" />
          <div className="absolute inset-0 flex items-center justify-center">
            <div className="w-2 h-2 rounded-full bg-green-400" />
          </div>
        </div>
      )}

      {overlay.label && (
        <div
          className="absolute -translate-x-1/2 bg-black/75 backdrop-blur text-green-300 text-[11px] font-medium rounded-lg px-2.5 py-1 whitespace-nowrap"
          style={
            overlay.shape === 'frame'
              ? { top: '14px', left: '50%' }
              : { top: '96px', left: `${overlay.x * 100}%` }
          }
        >
          {overlay.label}
        </div>
      )}
    </div>
  )
}