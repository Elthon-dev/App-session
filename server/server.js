import { WebSocketServer } from 'ws'
import http from 'node:http'

const PORT = Number(process.env.PORT || 8765)
const TOKEN = process.env.BRIDGE_TOKEN || 'dev-secret-change-me'

const server = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'content-type': 'application/json' })
    res.end(JSON.stringify({
      ok: true,
      port: PORT,
      phones: phoneSockets.size,
      agents: agentSockets.size,
    }))
    return
  }
  res.writeHead(200, { 'content-type': 'text/plain' })
  res.end('OpenBridge relay\n')
})

const wss = new WebSocketServer({ server })

const phoneSockets = new Map() // sessionId -> { ws, isAlive, lastSeen }
const agentSockets = new Set()

function relay(to, message) {
  if (to && to.readyState === to.OPEN) {
    to.send(JSON.stringify(message))
  }
}

function sendToPhone(message, exclude) {
  for (const [id, { ws }] of phoneSockets) {
    if (ws === exclude) continue
    relay(ws, message)
  }
}

wss.on('connection', (ws) => {
  ws.isAlive = true
  let platform = null
  let sessionId = null

  ws.on('pong', () => { ws.isAlive = true })

  ws.on('message', (raw) => {
    let msg
    try {
      msg = JSON.parse(raw.toString())
    } catch {
      return
    }

    if (msg.type === 'register') {
      if (msg.platform === 'agent') {
        if (msg.token !== TOKEN) {
          ws.send(JSON.stringify({ type: 'error', text: 'Invalid bridge token' }))
          ws.close()
          return
        }
        platform = 'agent'
        agentSockets.add(ws)
        console.log('[agent] connected')
        relay(ws, { type: 'ready', role: 'agent' })
        return
      }

      platform = 'phone'
      sessionId = String(msg.sessionId || crypto.randomUUID().slice(0, 4))
      phoneSockets.set(sessionId, { ws, lastSeen: Date.now() })
      console.log(`[phone] ${sessionId} connected  (${phoneSockets.size} phone(s))`)
      relay(ws, { type: 'ready', role: 'phone', sessionId })
      // let the agent know a phone arrived
      for (const agent of agentSockets) {
        relay(agent, { type: 'peer', sessionId })
      }
      return
    }

    // Relay between peers
    if (platform === 'phone') {
      if (msg.type === 'chat') {
        const backup = new Date().toLocaleTimeString()
        console.log(`[phone ${sessionId}] chat: ${String(msg.text).slice(0, 80)}`)
        const note = JSON.parse(JSON.stringify(msg))
        note.from = 'phone'
        note.sessionId = sessionId
        for (const agent of agentSockets) relay(agent, note)
      } else if (msg.type === 'pong') {
        // keepalive
      } else {
        const note = JSON.parse(JSON.stringify(msg))
        note.from = 'phone'
        note.sessionId = sessionId
        for (const agent of agentSockets) relay(agent, note)
      }
    } else if (platform === 'agent') {
      const note = JSON.parse(JSON.stringify(msg))
      note.from = 'agent'
      sendToPhone(note)
    }
  })

  ws.on('close', () => {
    if (platform === 'agent') {
      agentSockets.delete(ws)
      console.log('[agent] disconnected')
    } else if (platform === 'phone' && sessionId) {
      phoneSockets.delete(sessionId)
      console.log(`[phone] ${sessionId} disconnected`)
      for (const agent of agentSockets) {
        relay(agent, { type: 'peer-left', sessionId })
      }
    }
  })
})

setInterval(() => {
  for (const ws of wss.clients) {
    if (!ws.isAlive) {
      ws.terminate()
      continue
    }
    ws.isAlive = false
    ws.ping()
  }
}, 30_000)

server.listen(PORT, '0.0.0.0', () => {
  console.log(`OpenBridge relay listening on ws://0.0.0.0:${PORT}`)
  console.log(`Set BRIDGE_TOKEN=${TOKEN} on agent side`)
})