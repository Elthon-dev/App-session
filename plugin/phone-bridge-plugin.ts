import { type Plugin, tool } from '@opencode-ai/plugin'
import { mkdirSync, writeFileSync, unlinkSync, readdirSync, existsSync } from 'node:fs'

const BRIDGE_URL = process.env.BRIDGE_URL || 'ws://127.0.0.1:8765'
const BRIDGE_TOKEN = process.env.BRIDGE_TOKEN || 'dev-secret-change-me'

let agent: ReturnType<typeof Object> | null = null

export const PhoneBridgePlugin: Plugin = async ({ client }) => {
  const ws = globalThis.WebSocket
  let socket = null as any
  let phone = null as string | null
  let currentSessionID = null as string | null
  let latestFramePath = null as string | null
  let reconnectTimer = null as any

  let lastForwarded: string | null = null

  const forward = (t: string) => {
    const clean = String(t || '')
    if (!clean.trim() || !phone) return
    if (clean === lastForwarded) return
    lastForwarded = clean
    send({ type: 'chat', text: clean })
  }

  const framesDir = `${process.cwd()}/.bridge-frames`
  if (!existsSync(framesDir)) mkdirSync(framesDir, { recursive: true })

  const send = (msg: Record<string, unknown>) => {
    if (socket && socket.readyState === 1) {
      socket.send(JSON.stringify(msg))
    }
  }

  const connect = () => {
    try {
      socket = new ws(BRIDGE_URL)

      socket.onopen = () => {
        send({ type: 'register', platform: 'agent', token: BRIDGE_TOKEN })
        console.log('[openbridge] relay connected')
      }

      socket.onmessage = async (event: any) => {
        const data = JSON.parse(String(event.data))

        if (data.type === 'ready') return
        if (data.type === 'peer') {
          phone = data.sessionId || phone
          console.log(`[openbridge] phone joined: ${phone}`)
          return
        }
        if (data.type === 'peer-left') {
          phone = null
        }

        if (data.type === 'chat' && data.from === 'phone') {
          const text = String(data.text || '')
          console.log(`[openbridge] phone: ${text.slice(0, 120)}`)
          try {
            // Deliver into the most recently active session (the one the user
            // is actually using), not whatever got created last.
            let sessionID: string | null = null
            try {
              const list: any = await client.session.list()
              const latest = (list?.data ?? [])
                .sort(
                  (a: any, b: any) =>
                    new Date(b.time?.updated ?? b.time?.created ?? 0).getTime() -
                    new Date(a.time?.updated ?? a.time?.created ?? 0).getTime()
                )[0]
              if (latest?.id) sessionID = latest.id
            } catch {}
            if (!sessionID) {
              const created = await client.session.create({
                query: { directory: process.cwd() },
              })
              sessionID = created?.data?.id
              if (!sessionID) throw new Error('Could not create a session')
            }
            currentSessionID = sessionID
            lastForwarded = null
            const res: any = await client.session.prompt({
              path: { id: sessionID },
              body: { parts: [{ type: 'text', text }] },
            })
            const parts = res?.data?.info?.parts ?? res?.data?.parts ?? res?.data ?? []
            for (const p of parts) {
              if (p?.type === 'text' && p.text) forward(p.text)
            }
          } catch (err: any) {
            send({ type: 'chat', text: `⚠️ Could not reach Opencode: ${err?.message}` })
          }
          return
        }

        if (data.type === 'screen' && data.from === 'phone') {
          const base64 = String(data.image || '').split(',')[1] || ''
          if (base64.length > 0) {
            const file = `${framesDir}/frame-${Date.now()}.jpg`
            writeFileSync(file, Buffer.from(base64, 'base64'))
            try {
              if (readdirSync(framesDir).length > 60) {
                readdirSync(framesDir)
                  .sort()
                  .slice(0, 20)
                  .forEach((f) => unlinkSync(`${framesDir}/${f}`))
              }
            } catch {}
            latestFramePath = file
          }
          return
        }
      }

      socket.onerror = () => {}
      socket.onclose = () => {
        socket = null
        if (!reconnectTimer) {
          reconnectTimer = setTimeout(() => {
            reconnectTimer = null
            connect()
          }, 2000)
        }
      }
    } catch (err: any) {
      console.error('[openbridge] connection error:', err?.message)
      if (!reconnectTimer) {
        reconnectTimer = setTimeout(() => {
          reconnectTimer = null
          connect()
        }, 2000)
      }
    }
  }

  connect()
  agent = client

  return {
    tool: {
      phone_screenshot: tool({
        description:
          'Get the latest screenshot captured from the phone connected via OpenBridge. Returns the file path of a saved JPEG. Use when you need to see the phone screen.',
        args: {},
        async execute() {
          if (!phone) {
            return 'No phone connected. Ask the user to open the OpenBridge app on their phone, connect to the relay, and tap "Share screen".'
          }
          if (!latestFramePath) {
            return 'No frames received yet. Ask the user to start sharing their screen, then wait a moment and retry.'
          }
          return `Latest phone screenshot: ${latestFramePath}`
        },
      }),

      phone_overlay: tool({
        description:
          'Draw a visual guide on the phone screen to tell the user where to tap or swipe. The phone can only be controlled by the user physically, so use overlays to direct them and explain each step.',
        args: {
          shape: tool.schema.enum(['tap', 'swipe', 'frame']).describe('tap highlights a point to press, swipe shows a direction to drag, frame outlines the entire screen'),
          x: tool.schema.number().describe('horizontal position as a fraction (0..1) of screen width'),
          y: tool.schema.number().describe('vertical position as a fraction (0..1) of screen height'),
          dx: tool.schema.number().optional().describe('for swipe: horizontal delta as a fraction (0..1)'),
          dy: tool.schema.number().optional().describe('for swipe: vertical delta as a fraction (0..1)'),
          label: tool.schema.string().optional().describe('short instruction shown on screen (max ~40 chars)'),
        },
        async execute(args) {
          if (!phone) return 'No phone connected.'
          send({
            type: 'overlay',
            shape: args.shape || 'tap',
            x: args.x ?? 0.5,
            y: args.y ?? 0.5,
            dx: args.dx,
            dy: args.dy,
            label: args.label,
          })
          return `Overlay sent to phone (${args.shape || 'tap'}${args.label ? `, "${args.label}"` : ''}). Now explain the action to the user in chat.`
        },
      }),

      phone_notify: tool({
        description: 'Send a short message and a light vibration to the connected phone.',
        args: {
          text: tool.schema.string().describe('the message to show on the phone'),
        },
        async execute(args) {
          if (!phone) return 'No phone connected.'
          send({ type: 'toast', text: args.text })
          send({ type: 'vibrate', duration: 80 })
          return 'Delivered to phone.'
        },
      }),

      phone_open: tool({
        description: 'Open a URL in the browser on the connected phone.',
        args: {
          url: tool.schema.string().describe('http(s) URL to open'),
        },
        async execute(args) {
          if (!phone) return 'No phone connected.'
          send({ type: 'open', url: args.url })
          return `Opened ${args.url} on the phone.`
        },
      }),
    },

    event: async ({ event }) => {
      const e = event as any
      switch (e.type) {
        case 'session.created': {
          currentSessionID = e.properties?.info?.id || currentSessionID
          send({ type: 'chat', text: 'Connected. I can see your phone — ask me anything, or ask me to walk you through a task on your screen.' })
          break
        }
        case 'message.part.updated': {
          const part = e.properties?.part
          if (part?.type === 'text' && typeof part.text === 'string' && part.text.trim()) {
            forward(part.text)
          }
          break
        }
        case 'session.idle': {
          const alreadySent = lastForwarded != null
          lastForwarded = null
          if (!alreadySent) send({ type: 'chat', text: 'Done.' })
          break
        }
      }
    },
  }
}