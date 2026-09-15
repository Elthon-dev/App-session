import { useState, useRef, useCallback, useEffect } from 'react'

const QUALITY = {
  low: { fps: 2, width: 480, height: 360, imageQuality: 0.35 },
  medium: { fps: 5, width: 720, height: 540, imageQuality: 0.5 },
  high: { fps: 10, width: 960, height: 720, imageQuality: 0.7 },
}

export function useScreenCapture(onFrame) {
  const [streaming, setStreaming] = useState(false)
  const [error, setError] = useState(null)
  const [quality, setQuality] = useState('low')
  const [stream, setStream] = useState(null)
  const streamRef = useRef(null)
  const intervalRef = useRef(null)
  const cfg = QUALITY[quality]

  const stop = useCallback(() => {
    if (intervalRef.current) {
      clearInterval(intervalRef.current)
      intervalRef.current = null
    }
    streamRef.current?.getTracks().forEach(t => t.stop())
    streamRef.current = null
    setStream(null)
    setStreaming(false)
  }, [])

  const start = useCallback(async () => {
    if (streamRef.current) return
    setError(null)
    try {
      if (!navigator.mediaDevices?.getDisplayMedia) {
        setError('Screen capture is not supported in this webview. Open the OpenBridge PWA in Chrome/Safari to share your screen, or keep using chat here.')
        setStreaming(false)
        return
      }
      const ms = await navigator.mediaDevices.getDisplayMedia({
        video: { frameRate: { ideal: cfg.fps }, width: { ideal: cfg.width } },
        audio: false,
      })
      streamRef.current = ms
      setStream(ms)

      const video = document.createElement('video')
      video.srcObject = ms
      video.muted = true
      video.playsInline = true
      await video.play()

      const canvas = document.createElement('canvas')
      canvas.width = cfg.width
      canvas.height = cfg.height
      const ctx = canvas.getContext('2d')

      let last = 0
      const sendFrame = () => {
        if (video.videoWidth === 0 || video.readyState < 2) return
        const scale = Math.min(cfg.width / video.videoWidth, cfg.height / video.videoHeight)
        const w = Math.round(video.videoWidth * scale)
        const h = Math.round(video.videoHeight * scale)
        ctx.fillStyle = '#000'
        ctx.fillRect(0, 0, canvas.width, canvas.height)
        ctx.drawImage(video, (canvas.width - w) / 2, (canvas.height - h) / 2, w, h)
        try {
          onFrame?.(canvas.toDataURL('image/jpeg', cfg.imageQuality))
        } catch {}
      }

      sendFrame()
      intervalRef.current = setInterval(sendFrame, 1000 / cfg.fps)
      setStreaming(true)

      ms.getVideoTracks()[0].onended = stop
    } catch (err) {
      setError(err?.message || 'Screen capture failed')
      setStreaming(false)
    }
  }, [onFrame, stop, cfg.fps, cfg.width, cfg.height, cfg.imageQuality])

  useEffect(() => () => stop(), [stop])

  return { streaming, error, quality, setQuality, stream, start, stop }
}