import { useState } from 'react'
import { Plug, Link2 } from 'lucide-react'

export default function ConnectionView({ onConnect, serverUrl, onServerUrlChange }) {
  const [input, setInput] = useState(serverUrl)
  const [error, setError] = useState('')

  const handleConnect = () => {
    const url = input.trim()
    if (!url.startsWith('ws://') && !url.startsWith('wss://')) {
      setError('Enter a valid WebSocket URL (ws:// or wss://)')
      return
    }
    setError('')
    onServerUrlChange(url)
    onConnect(url)
  }

  return (
    <div className="flex flex-col items-center justify-center h-full px-8 animate-fade-in">
      <div className="w-16 h-16 rounded-2xl bg-gradient-to-br from-[var(--nord10)] to-[var(--nord9)] flex items-center justify-center mb-6 shadow-[0_0_40px_rgba(143,188,187,0.15)]">
        <Plug size={28} className="text-[var(--nord6)]" />
      </div>

      <h2 className="text-xl font-semibold text-[var(--nord6)] mb-1.5">Connect to Opencode</h2>
      <p className="text-sm text-[var(--nord3)] mb-8 text-center leading-relaxed">
        Start a bridge session to chat, share your screen,<br />
        and let Opencode guide you on your phone.
      </p>

      <div className="w-full max-w-sm">
        <div className="flex items-center gap-2.5 bg-[var(--surface)] border border-[var(--border)] rounded-xl px-3.5 py-3 focus-within:border-[var(--border-focus)] focus-within:ring-1 focus-within:ring-[var(--nord3)] transition-all">
          <Link2 size={16} className="text-[var(--nord3)] shrink-0" />
          <input
            value={input}
            onChange={e => setInput(e.target.value)}
            onKeyDown={e => e.key === 'Enter' && handleConnect()}
            placeholder="ws://127.0.0.1:8765"
            className="bg-transparent flex-1 outline-none text-sm placeholder:text-[var(--nord3)]"
            spellCheck={false}
          />
        </div>

        {error && <p className="text-[12px] text-[var(--nord11)] mt-2">{error}</p>}

        <button
          onClick={handleConnect}
          className="mt-4 w-full bg-[var(--accent)] hover:bg-[var(--nord14)] active:scale-[0.98] text-[var(--accent-contrast)] font-semibold text-sm rounded-xl py-3.5 transition-all duration-150 shadow-[0_0_20px_rgba(163,190,140,0.15)]"
        >
          Connect
        </button>
      </div>

      <div className="mt-8 flex flex-col items-center gap-1.5">
        <div className="flex items-center gap-2 text-[12px] text-[var(--nord3)]">
          <span className="w-1.5 h-1.5 rounded-full bg-[var(--nord14)] animate-pulse-dot" />
          Bridge server must be running
        </div>
        <p className="text-[11px] text-[var(--nord3)]/80">
          Relay: <code className="bg-[var(--surface)] border border-[var(--border)] rounded px-1.5 py-0.5 text-[10px]">node server/server.js</code>
        </p>
      </div>
    </div>
  )
}