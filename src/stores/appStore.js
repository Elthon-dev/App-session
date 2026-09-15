import { useState, useCallback, useRef } from 'react'

const DEFAULT_SERVER = 'ws://localhost:8765'

export function useAppStore() {
  const [view, setView] = useState('connection')
  const [serverUrl, setServerUrl] = useState(
    () => localStorage.getItem('bridge-server') || DEFAULT_SERVER
  )
  const [connectionState, setConnectionState] = useState('disconnected')
  const [messages, setMessages] = useState([])
  const [streaming, setStreaming] = useState(false)
  const [remoteControlActive, setRemoteControlActive] = useState(false)
  const [sessionId, setSessionId] = useState(null)
  const [overlay, setOverlay] = useState(null)
  const wsRef = useRef(null)

  const send = useCallback((msg) => {
    const ws = wsRef.current
    if (!ws || ws.readyState !== WebSocket.OPEN) return
    ws.send(JSON.stringify(msg))
  }, [])

  const connect = useCallback((url) => {
    if (wsRef.current?.readyState === WebSocket.OPEN) return

    const wsUrl = url || serverUrl
    localStorage.setItem('bridge-server', wsUrl)
    setConnectionState('connecting')
    setMessages([])

    let ws
    try {
      ws = new WebSocket(wsUrl)
      wsRef.current = ws
    } catch {
      setConnectionState('error')
      return
    }

    ws.onopen = () => {
      setConnectionState('connected')
      const id = crypto.randomUUID().slice(0, 4)
      setSessionId(id)
      ws.send(JSON.stringify({ type: 'register', platform: 'phone', sessionId: id }))
      setView('chat')
    }

    ws.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data)
        if (data.type === 'chat') {
          setMessages(prev => [...prev, {
            id: crypto.randomUUID(),
            role: 'assistant',
            text: data.text,
            timestamp: Date.now()
          }])
        } else if (data.type === 'overlay') {
          setOverlay({
            shape: data.shape || 'circle',
            x: data.x,
            y: data.y,
            dx: data.dx,
            dy: data.dy,
            label: data.label,
            ttl: data.ttl ?? 4000,
            token: Date.now(),
          })
        } else if (data.type === 'toast') {
          setMessages(prev => [...prev, {
            id: crypto.randomUUID(),
            role: 'system',
            text: data.text,
            timestamp: Date.now()
          }])
        } else if (data.type === 'vibrate') {
          try { navigator.vibrate?.(data.duration || 120) } catch {}
        } else if (data.type === 'open') {
          window.open(data.url, '_blank')
        } else if (data.type === 'ping') {
          ws.send(JSON.stringify({ type: 'pong' }))
        }
      } catch {}
    }

    ws.onerror = () => setConnectionState('error')
    ws.onclose = () => {
      wsRef.current = null
      setConnectionState('disconnected')
      setOverlay(null)
    }
  }, [serverUrl])

  const disconnect = useCallback(() => {
    wsRef.current?.close()
    wsRef.current = null
    setConnectionState('disconnected')
    setView('connection')
    setOverlay(null)
  }, [])

  const sendChat = useCallback((text) => {
    if (!wsRef.current || wsRef.current.readyState !== WebSocket.OPEN) return
    setMessages(prev => [...prev, {
      id: crypto.randomUUID(),
      role: 'user',
      text,
      timestamp: Date.now()
    }])
    wsRef.current.send(JSON.stringify({ type: 'chat', text }))
  }, [])

  const sendFrame = useCallback((dataUrl) => {
    if (!wsRef.current || wsRef.current.readyState !== WebSocket.OPEN) return
    wsRef.current.send(JSON.stringify({ type: 'screen', image: dataUrl }))
  }, [])

  const sendGesture = useCallback((gesture) => {
    if (!wsRef.current || wsRef.current.readyState !== WebSocket.OPEN) return
    wsRef.current.send(JSON.stringify({ type: 'gesture', ...gesture }))
  }, [])

  const clearOverlay = useCallback(() => setOverlay(null), [])

  return {
    view, setView,
    serverUrl, setServerUrl,
    connectionState,
    messages,
    streaming, setStreaming,
    remoteControlActive, setRemoteControlActive,
    sessionId,
    overlay, setOverlay,
    clearOverlay,
    connect, disconnect,
    sendChat,
    sendFrame,
    sendGesture,
  }
}