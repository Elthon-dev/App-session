import { Wifi, WifiOff, Phone } from 'lucide-react'

const statusConfig = {
  connected: { color: 'text-green-500', dot: 'bg-green-500', label: 'Connected' },
  connecting: { color: 'text-yellow-500', dot: 'bg-yellow-500', label: 'Connecting…' },
  error: { color: 'text-red-500', dot: 'bg-red-500', label: 'Error' },
  disconnected: { color: 'text-zinc-500', dot: 'bg-zinc-500', label: 'Offline' },
}

export default function StatusBar({ state, sessionId, onDisconnect }) {
  const cfg = statusConfig[state] || statusConfig.disconnected
  const connected = state === 'connected'

  return (
    <header className="flex items-center justify-between px-4 py-3 border-b border-zinc-800/60 bg-[var(--surface)]/80 backdrop-blur-md sticky top-0 z-20">
      <div className="flex items-center gap-2.5">
        <div className="w-7 h-7 rounded-lg bg-gradient-to-br from-green-500 to-emerald-700 flex items-center justify-center">
          <Phone size={14} className="text-white" />
        </div>
        <div>
          <h1 className="text-sm font-semibold tracking-wide">OpenBridge</h1>
          <div className="flex items-center gap-1.5">
            <span className={`w-1.5 h-1.5 rounded-full ${cfg.dot} ${state === 'connecting' ? 'animate-pulse-dot' : ''}`} />
            <span className={`text-[11px] ${cfg.color}`}>{cfg.label}</span>
            {sessionId && <span className="text-[11px] text-zinc-600">· {sessionId}</span>}
          </div>
        </div>
      </div>
      {connected && (
        <button
          onClick={onDisconnect}
          className="flex items-center gap-1.5 text-[11px] text-zinc-400 hover:text-red-400 transition-colors px-2 py-1 rounded-lg hover:bg-red-500/10"
        >
          <WifiOff size={13} />
          End session
        </button>
      )}
      {!connected && state === 'disconnected' && (
        <div className="text-[11px] text-zinc-600 flex items-center gap-1.5">
          <Wifi size={12} />
          No session
        </div>
      )}
    </header>
  )
}