import { Wifi, WifiOff, Phone } from 'lucide-react'

const statusConfig = {
  connected: { color: 'text-(--nord14)', dot: 'bg-(--nord14)', label: 'Connected' },
  connecting: { color: 'text-(--nord13)', dot: 'bg-(--nord13)', label: 'Connecting…' },
  error: { color: 'text-(--nord11)', dot: 'bg-(--nord11)', label: 'Error' },
  disconnected: { color: 'text-(--nord3)', dot: 'bg-(--nord3)', label: 'Offline' },
}

export default function StatusBar({ state, sessionId, onDisconnect }) {
  const cfg = statusConfig[state] || statusConfig.disconnected
  const connected = state === 'connected'

  return (
    <header className="header flex items-center justify-between border-b border-[var(--border)] bg-[var(--surface)]/80 backdrop-blur-md sticky top-0 z-20">
      <div className="flex items-center gap-2.5 pt-1 pb-3">
        <div className="w-7 h-7 rounded-lg bg-gradient-to-br from-[var(--nord10)] to-[var(--nord9)] flex items-center justify-center">
          <Phone size={14} className="text-[var(--nord6)]" />
        </div>
        <div>
          <h1 className="text-sm font-semibold tracking-wide text-[var(--nord6)]">OpenBridge</h1>
          <div className="flex items-center gap-1.5">
            <span className={`w-1.5 h-1.5 rounded-full ${cfg.dot} ${state === 'connecting' ? 'animate-pulse-dot' : ''}`} />
            <span className={`text-[11px] ${cfg.color}`}>{cfg.label}</span>
            {sessionId && <span className="text-[11px] text-[var(--nord3)]">· {sessionId}</span>}
          </div>
        </div>
      </div>
      {connected && (
        <button
          onClick={onDisconnect}
          className="mb-2 flex items-center gap-1.5 text-[11px] text-[var(--nord3)] hover:text-[var(--nord11)] transition-colors px-2 py-1 rounded-lg hover:bg-red-500/10"
        >
          <WifiOff size={13} />
          End session
        </button>
      )}
      {!connected && state === 'disconnected' && (
        <div className="mb-2 text-[11px] text-[var(--nord3)] flex items-center gap-1.5">
          <Wifi size={12} />
          No session
        </div>
      )}
    </header>
  )
}