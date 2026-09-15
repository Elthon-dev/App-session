import { useState, useRef, useEffect } from 'react'
import { Send, Scan } from 'lucide-react'

export default function ChatView({ messages, onSend, onStartScreenShare }) {
  const [input, setInput] = useState('')
  const bottomRef = useRef(null)

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth', block: 'end' })
  }, [messages])

  const handleSend = (e) => {
    if (e.shiftKey && e.key === 'Enter') return
    if (e.key !== 'Enter') return
    e.preventDefault()
    const text = input.trim()
    if (!text) return
    onSend(text)
    setInput('')
  }

  const handleSendClick = () => {
    const text = input.trim()
    if (!text) return
    onSend(text)
    setInput('')
  }

  return (
    <div className="flex flex-col h-full">
      {messages.length === 0 ? (
        <div className="flex-1 flex flex-col items-center justify-center text-center px-6">
          <Scan size={32} className="text-zinc-700 mb-3" />
          <h3 className="text-[15px] font-medium text-zinc-300 mb-1.5">Session ready</h3>
          <p className="text-[13px] text-zinc-500 max-w-[280px] leading-relaxed">
            Talk to Opencode, or share your screen when you need hands-on help.
          </p>
          <button
            onClick={onStartScreenShare}
            className="mt-4 flex items-center gap-2 text-[13px] bg-[var(--surface)] hover:bg-[var(--surface-hover)] border border-[var(--border)] rounded-lg px-3.5 py-2 transition-all active:scale-[0.97]"
          >
            <Scan size={14} className="text-green-500" />
            Share screen & control
          </button>
        </div>
      ) : (
        <div className="flex-1 overflow-y-auto px-4 py-4 space-y-2.5">
          {messages.map((msg) => (
            <div
              key={msg.id}
              className={`flex ${msg.role === 'user' ? 'justify-end' : 'justify-start'} animate-fade-in`}
            >
              {msg.role === 'assistant' && (
                <div className="w-6 h-6 rounded-full bg-gradient-to-br from-green-500 to-emerald-700 flex items-center justify-center mr-2 mt-0.5 shrink-0">
                  <span className="text-[10px] font-bold text-white">O</span>
                </div>
              )}
              <div
                className={`max-w-[78%] rounded-2xl px-3.5 py-2.5 text-[13.5px] leading-relaxed whitespace-pre-wrap break-words ${
                  msg.role === 'user'
                    ? 'bg-[var(--accent)] text-black rounded-br-sm'
                    : 'bg-[var(--surface)] border border-[var(--border)] text-zinc-200 rounded-bl-sm'
                } ${msg.role === 'system' ? 'bg-transparent border-none text-zinc-500 text-[12px] italic max-w-full' : ''}`}
              >
                {msg.text}
              </div>
            </div>
          ))}
          <div ref={bottomRef} />
        </div>
      )}

      <div className="border-t border-[var(--border)] p-3 bg-[var(--bg)]">
        <div className="flex items-center gap-2">
          <button
            onClick={onStartScreenShare}
            title="Share screen"
            className="w-9 h-9 rounded-xl bg-[var(--surface)] hover:bg-[var(--surface-hover)] border border-[var(--border)] flex items-center justify-center text-zinc-400 hover:text-green-400 transition-all active:scale-95"
          >
            <Scan size={16} />
          </button>
          <input
            value={input}
            onChange={e => setInput(e.target.value)}
            onKeyDown={handleSend}
            placeholder="Message Opencode…"
            className="flex-1 bg-[var(--surface)] hover:bg-[var(--surface-hover)] focus:bg-[var(--surface-hover)]/80 border border-[var(--border)] rounded-xl px-4 py-2.5 text-[13.5px] outline-none focus:border-[var(--border-focus)] transition-colors"
          />
          <button
            onClick={handleSendClick}
            disabled={!input.trim()}
            className="w-9 h-9 rounded-xl bg-[var(--accent)] hover:bg-green-400 disabled:bg-zinc-800 disabled:text-zinc-600 flex items-center justify-center text-black transition-all active:scale-95 disabled:active:scale-100"
          >
            <Send size={15} />
          </button>
        </div>
        <div className="mt-2 px-0.5">
          <span className="text-[10px] text-zinc-600">Enter to send</span>
        </div>
      </div>
    </div>
  )
}