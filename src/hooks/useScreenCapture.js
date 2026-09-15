import { useState, useRef, useCallback, useEffect } from 'react'
import {
  isNative,
  nativeStartCapture,
  nativeCaptureFrame,
  nativeStopCapture,
} from '../lib/nativeCapture'

const QUALITY = {
  low: { fps: 2, width: 480, height: 360, imageQuality: 0.35 },
  medium: { fps: 5, width: 720, height: 540, imageQuality: 0.5 },
  high: { fps: 10, width: 960, height: 720, imageQuality: 0.7 },
}

const NATIVE_DIMS = { low: [400, 712], medium: [480, 854], high: [720, 1280] }

export function useScreenCapture(onFrame) {
  const [streaming, setStreaming] = useState(false)
  const [error, setError] = useState(null)
  const [quality, setQuality] = useState('low')
  const [stream, setStream] = useState(null)
  const [lastFrame, setLastFrame] = useState(null)
  const [native, setNative] = useState(false)
  const streamRef = useRef(null)
  const intervalRef = useRef(null)

  const stop = useCallback(() => {
    if (intervalRef.current) {
      clearInterval(intervalRef.current)
      intervalRef.current = null
    }
    streamRef.current?.getTracks().forEach(t => t.stop())
    streamRef.current = null
    setStream(null)
    setStreaming(false)
    setNative(false)
    if (isNative()) nativeStopCapture()
  }, [])

  const startNative = useCallback(async () => {
    const dims = NATIVE_DIMS[quality] || NATIVE_DIMS.low
    try {
      await nativeStartCapture({ width: dims[0], height: dims[1] })
      setNative(true)
      setStreaming(true)

      const fps = QUALITY[quality].fps
      const sendFrame = async () => {
        try {
          const dataUrl = await nativeCaptureFrame(40)
          setLastFrame(dataUrl)
          onFrame?.(dataUrl)
        } catch {}
      }
      await sendFrame()
      intervalRef.current = setInterval(sendFrame, 1000 / fps)
    } catch (err) {
      setError(err?.message || 'Screen capture permission denied')
      setStreaming(false)
      setNative(false)
    }
  }, [onFrame, quality])

  const start = useCallback(async () => {
    if (streaming) return
    setError(null)

    if (isNative()) {
      await startNative()
      return
    }

    try {
      if (!navigator.mediaDevices?.getDisplayMedia) {
        setError('Screen capture is not supported in this webview. On the APK this uses native capture — please update the app.')
        setStreaming(false)
        return
      }
      const cfg = QUALITY[quality]
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

      const sendFrame = () => {
        if (video.videoWidth === 0 || video.readyState < 2) return
        const scale = Math.min(cfg.width / video.videoWidth, cfg.height / video.videoHeight)
        const w = Math.round(video.videoWidth * scale)
        const h = Math.round(video.videoHeight * scale)
        ctx.fillStyle = '#000'
        ctx.fillRect(0, 0, canvas.width, canvas.height)
        ctx.drawImage(video, (canvas.width - w) / 2, (canvas.height - h) / 2, w, h)
        try {
          const dataUrl = canvas.toDataURL('image/jpeg', cfg.imageQuality)
          setLastFrame(dataUrl)
          onFrame?.(dataUrl)
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
  }, [onFrame, stop, quality, startNative, streaming])

  useEffect(() => () => stop(), [stop])

  return { streaming, error, quality, setQuality, stream, native, lastFrame, start, stop }
}