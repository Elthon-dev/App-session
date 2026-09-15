import { useRef, useEffect } from 'react'
import { ArrowLeft, Hand, MousePointer, MonitorUp } from 'lucide-react'
import { useScreenCapture } from '../hooks/useScreenCapture'
import GestureOverlay from './GestureOverlay'

export default function ScreenShareView({
  onFrame,
  onStop,
  onBackToChat,
  remoteControlActive,
  onRemoteControlChange,
  overlay,
  onOverlayClear,
  onGesture,
}) {
  const previewRef = useRef(null)
  const { streaming, error, quality, setQuality, stream, start, stop } =
    useScreenCapture(onFrame)

  useEffect(() => {
    if (previewRef.current) previewRef.current.srcObject = stream || null
  }, [stream])

  const handleStop = () => {
    stop()
    onRemoteControlChange(false)
    onStop()
  }

  const handleBack = () => {
    stop()
    onRemoteControlChange(false)
    onBackToChat()
  }

  const handlePreviewTap = (e) => {
    if (!remoteControlActive) return
    const video = previewRef.current
    if (!video) return
    const rect = video.getBoundingClientRect()
    const x = (e.clientX - rect.left) / rect.width
    const y = (e.clientY - rect.top) / rect.height
    onGesture?.({ type: 'tap', x, y })
  }

  return (
    <div className="flex flex-col h-full">
      <div className="flex items-center justify-between px-4 py-3 border-b border-[var(--border)] bg-[var(--surface)]/60">
        <button
          onClick={handleBack}
          className="flex items-center gap-1.5 text-[12px] text-zinc-400 hover:text-white transition-colors"
        >
          <ArrowLeft size={15} />
          Chat
        </button>
        <span className="flex items-center gap-2 text-[12px] text-zinc-400">
          <span className={`w-2 h-2 rounded-full ${streaming ? 'bg-green-500 animate-pulse-dot' : 'bg-zinc-600'}`} />
          {streaming ? 'Sharing' : 'Idle'}
        </span>
      </div>

      <div className="relative flex-1 flex flex-col min-h-0">
        <div className="relative flex-1 bg-black grid place-items-center min-h-0 overflow-hidden">
          <div className="w-full h-full grid place-items-center" onClick={handlePreviewTap}>
            {!stream && (
              <div className="absolute inset-0 flex flex-col items-center justify-center text-center px-8">
                <div className="mx-auto w-14 h-14 rounded-full border border-dashed border-zinc-700 flex items-center justify-center mb-4">
                  <Hand size={22} className="text-zinc-700" />
                </div>
                <p className="text-[15px] text-zinc-400 font-medium mb-1.5">Nothing sharing</p>
                <p className="text-[12px] text-zinc-600 max-w-[260px] mx-auto leading-relaxed">
                  You'll be asked to pick a screen or app. Opencode sees your phone and guides you step by step.
                </p>
                {error && <p className="text-[11px] text-red-400 mt-2">{error}</p>}
                <button
                  onClick={start}
                  className="mt-5 flex items-center gap-2 bg-[var(--accent)] hover:bg-green-400 text-black text-[13px] font-semibold rounded-full px-6 py-2.5 transition-all active:scale-[0.97]"
                >
                  <MonitorUp size={15} />
                  Share screen
                </button>
              </div>
            )}
            <video ref={previewRef} autoPlay playsInline muted className="w-full h-full object-contain" />
          </div>

          {streaming && (
            <GestureOverlay
              overlay={overlay}
              onExpire={() => onOverlayClear?.()}
            />
          )}
        </div>

        <div className="border-t border-[var(--border)] bg-[var(--surface)] p-3.5">
          <div className="flex items-center justify-between mb-3">
            <div>
              <h4 className="text-[13px] font-medium text-zinc-300">Remote control</h4>
              <p className="text-[10.5px] text-zinc-600 mt-0.5">
                Opencode overlays guides · tap preview to assist
              </p>
            </div>
            <button
              onClick={() => onRemoteControlChange(!remoteControlActive)}
              disabled={!streaming}
              className={`flex items-center gap-2 text-[12px] font-medium rounded-lg px-3 py-2 transition-all active:scale-95 disabled:opacity-40 disabled:active:scale-100 border ${
                remoteControlActive
                  ? 'bg-green-500/10 border-green-500/30 text-green-400'
                  : 'bg-zinc-800/40 border-zinc-700 text-zinc-400 hover:border-zinc-600'
              }`}
            >
              <MousePointer size={14} />
              {remoteControlActive ? 'Assist on' : 'Assist off'}
            </button>
          </div>

          <div className="grid grid-cols-2 gap-3">
            <label className="block">
              <span className="text-[10.5px] text-zinc-500 mb-1 block">Quality</span>
              <select
                value={quality}
                onChange={e => setQuality(e.target.value)}
                className="w-full bg-black/30 border border-[var(--border)] rounded-lg px-2.5 py-1.5 text-[12px] text-zinc-300 outline-none"
              >
                <option value="low">Low · data saving</option>
                <option value="medium">Medium</option>
                <option value="high">High</option>
              </select>
            </label>
            <div className="flex items-end">
              <button
                onClick={streaming ? handleStop : start}
                className={`w-full text-[12px] font-semibold rounded-lg py-1.5 border transition-all active:scale-[0.98] ${
                  streaming
                    ? 'bg-red-500/10 border-red-500/30 text-red-400 hover:bg-red-500/20'
                    : 'bg-zinc-800/40 border-zinc-700 text-zinc-300 hover:border-zinc-600'
                }`}
              >
                {streaming ? 'Stop sharing' : 'Start sharing'}
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}