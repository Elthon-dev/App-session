import { type Plugin, tool } from '@opencode-ai/plugin'
import { mkdirSync, writeFileSync, unlinkSync, readdirSync, existsSync } from 'node:fs'

const BRIDGE_URL = process.env.BRIDGE_URL || 'ws://127.0.0.1:8765'
const BRIDGE_TOKEN = process.env.BRIDGE_TOKEN || 'dev-secret-change-me'

let agent: ReturnType<typeof Object> | null = null

type SwarmStatus = 'pending' | 'thinking' | 'running' | 'done' | 'failed' | 'cancelled'

type SubAgent = {
  id: string
  name: string
  role: string
  status: SwarmStatus
  sessionID: string | null
  output: string
  detail: string
  startedAt: number
  endedAt: number | null
}

type SwarmRun = {
  id: string
  task: string
  subs: Map<string, SubAgent>
  summary: string | null
  cancelled: boolean
  startedAt: number
  endedAt: number | null
}

export const PhoneBridgePlugin: Plugin = async ({ client }) => {
  const ws = globalThis.WebSocket
  let socket = null as any
  let phone = null as string | null
  let currentSessionID = null as string | null
  let latestFramePath = null as string | null
  let reconnectTimer = null as any

  let lastForwarded: string | null = null
  let selectedModel: { providerID: string; modelID: string } | null = null
  let selectedAgent: string | null = null

  // ---- Swarm registry ----------------------------------------------------
  let swarm: SwarmRun | null = null
  const swarmHistory: SwarmRun[] = []
  const sessionToSub = new Map<string, { runId: string; subId: string }>()
  const cancelledRuns = new Set<string>()

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

  const extractText = (parts: any[]): string => {
    return (parts || [])
      .filter((p) => p?.type === 'text' && typeof p.text === 'string')
      .map((p) => p.text)
      .join('\n')
      .trim()
  }

  const listAgents = async (): Promise<Array<{ name: string; description: string; builtIn: boolean }>> => {
    try {
      const res: any = await client.app.agents()
      const data: any = res?.data
      const raw = Array.isArray(data) ? data : Array.isArray(data?.agents) ? data.agents : []
      return raw
        .filter((a: any) => a?.name)
        .map((a: any) => ({
          name: String(a.name),
          description: String(a?.description ?? ''),
          builtIn: !!a?.builtIn,
        }))
    } catch {
      return []
    }
  }

  // ---- Config ------------------------------------------------------------
  const sendConfig = async () => {
    try {
      const [providersRes, agentsRes, sessionRes]: any[] = await Promise.all([
        client.config.providers(),
        client.app.agents(),
        client.session.list(),
      ])
      const providersData: any = providersRes?.data
      const providers = Array.isArray(providersData)
        ? providersData
        : Array.isArray(providersData?.providers)
          ? providersData.providers
          : []
      const agentsData: any = agentsRes?.data
      const agentsRaw = Array.isArray(agentsData)
        ? agentsData
        : Array.isArray(agentsData?.agents)
          ? agentsData.agents
          : []
      const sessionsData: any = sessionRes?.data
      const sessions = Array.isArray(sessionsData)
        ? sessionsData
        : Array.isArray(sessionsData?.sessions)
          ? sessionsData.sessions
          : []

      const models: Array<{ providerID: string; modelID: string; name: string }> = []
      for (const p of providers) {
        const pModels = p?.models && typeof p.models === 'object' ? p.models : {}
        for (const m of Object.values(pModels)) {
          const mm = m as any
          const modelID = String(mm?.id ?? '')
          const name = String(mm?.name || mm?.id || '')
          if (modelID) {
            models.push({ providerID: String(p?.id ?? ''), modelID, name })
          }
        }
      }
      models.sort((a, b) => (a.providerID + a.modelID).localeCompare(b.providerID + b.modelID))

      const agents: Array<{ name: string; description: string; builtIn: boolean }> = []
      for (const a of agentsRaw) {
        if (a?.name) {
          agents.push({ name: String(a.name), description: String(a?.description ?? ''), builtIn: !!a?.builtIn })
        }
      }
      agents.sort((a, b) => String(a.builtIn).localeCompare(String(b.builtIn)) || a.name.localeCompare(b.name))

      let current: { model: { providerID: string; modelID: string } | null; agent: string | null } = {
        model: selectedModel,
        agent: selectedAgent,
      }
      try {
        const latest = [...sessions].sort(
          (a: any, b: any) =>
            new Date(b.time?.updated ?? b.time?.created ?? 0).getTime() -
            new Date(a.time?.updated ?? a.time?.created ?? 0).getTime()
        )[0]
        if (latest) {
          current = {
            model: selectedModel ?? latest?.model ?? null,
            agent: selectedAgent ?? latest?.agent ?? null,
          }
        }
      } catch {}
      send({ type: 'config', models, agents, current })
    } catch (err: any) {
      console.error('[openbridge] config fetch failed:', err?.message)
    }
  }

  // ---- Main session bridge ----------------------------------------------
  const latestSessionID = async (): Promise<string | null> => {
    try {
      const list: any = await client.session.list()
      const latest = (list?.data ?? []).sort(
        (a: any, b: any) =>
          new Date(b.time?.updated ?? b.time?.created ?? 0).getTime() -
          new Date(a.time?.updated ?? a.time?.created ?? 0).getTime()
      )[0]
      if (latest?.id) return latest.id
    } catch {}
    return null
  }

  const askMain = async (text: string) => {
    try {
      let sessionID = await latestSessionID()
      if (!sessionID) {
        const created: any = await client.session.create({ query: { directory: process.cwd() } })
        sessionID = created?.data?.id
        if (!sessionID) throw new Error('Could not create a session')
      }
      currentSessionID = sessionID
      lastForwarded = null
      const body: any = { parts: [{ type: 'text', text }] }
      if (selectedModel) body.model = selectedModel
      if (selectedAgent) body.agent = selectedAgent
      const res: any = await client.session.prompt({ path: { id: sessionID }, body })
      const parts = res?.data?.info?.parts ?? res?.data?.parts ?? res?.data ?? []
      for (const p of parts) {
        if (p?.type === 'text' && p.text) forward(p.text)
      }
    } catch (err: any) {
      send({ type: 'chat', text: `⚠️ Could not reach Opencode: ${err?.message}` })
    }
  }

  // ---- Swarm orchestration ----------------------------------------------
  const subtaskFor = (role: string, task: string): string => {
    const r = role.toLowerCase()
    if (r.includes('explore') || r.includes('research') || r.includes('search')) {
      return `You are the RESEARCH sub-agent of a swarm. Gather concrete, verifiable facts, context and constraints relevant to the master task below. Be dense and specific — bullet points, numbers, and any uncertainties.\n\nMASTER TASK: ${task}`
    }
    if (r.includes('plan') || r.includes('architect') || r.includes('design')) {
      return `You are the PLANNER sub-agent of a swarm. Produce a complete, actionable plan for the master task: ordered steps, key decisions and their rationale, dependencies, and risks.\n\nMASTER TASK: ${task}`
    }
    if (r.includes('human') || r.includes('critic') || r.includes('review')) {
      return `You are the CRITIC sub-agent of a swarm. Stress-test the obvious approach to the master task: find edge cases, failure modes, hidden assumptions and practical tradeoffs. End with a clear recommendation.\n\nMASTER TASK: ${task}`
    }
    if (r.includes('build') || r.includes('general') || r.includes('code')) {
      return `You are the BUILDER sub-agent of a swarm. Independently work out the strongest concrete answer/implementation for the master task. Be thorough but tight, and state assumptions.\n\nMASTER TASK: ${task}`
    }
    return `You are the "${role}" sub-agent of a swarm. Contribute your specialised perspective on the master task and return a focused, high-signal result.\n\nMASTER TASK: ${task}`
  }

  const runSubAgent = async (run: SwarmRun, sub: SubAgent, model: { providerID: string; modelID: string } | null) => {
    try {
      const created: any = await client.session.create({ query: { directory: process.cwd() } })
      const sid = created?.data?.id
      if (!sid) throw new Error('could not create sub-agent session')
      sub.sessionID = sid
      sessionToSub.set(sid, { runId: run.id, subId: sub.id })
      sub.status = 'running'
      sub.detail = 'deploying…'
      emitUpdate(run, sub)

      const body: any = { parts: [{ type: 'text', text: subtaskFor(sub.role, run.task) }] }
      if (model) body.model = model
      if (sub.role) body.agent = sub.role

      const res: any = await client.session.prompt({ path: { id: sid }, body })
      const parts = res?.data?.info?.parts ?? res?.data?.parts ?? res?.data ?? []
      const text = extractText(parts)
      sub.output = text || sub.output || '(no output)'
      sub.status = run.cancelled || cancelledRuns.has(run.id) ? 'cancelled' : 'done'
      sub.detail = sub.status === 'done' ? 'completed' : 'cancelled'
      sub.endedAt = Date.now()
      emitUpdate(run, sub)
    } catch (err: any) {
      sub.status = 'failed'
      sub.detail = err?.message ? String(err.message).slice(0, 240) : 'failed'
      sub.endedAt = Date.now()
      emitUpdate(run, sub)
    }
  }

  const emitUpdate = (run: SwarmRun, sub: SubAgent) => {
    send({
      type: 'swarm-update',
      id: run.id,
      agentId: sub.id,
      status: sub.status,
      text: sub.output || undefined,
      detail: sub.detail || undefined,
    })
  }

  const converge = async (run: SwarmRun, model: { providerID: string; modelID: string } | null): Promise<string> => {
    const sections = [...run.subs.values()]
      .map((s) => `## ${s.name} (${s.role}) — ${s.status}\n${s.output || s.detail || '(no output)'}`)
      .join('\n\n')
    const prompt = [
      'You are the synthesis core of an OpenBridge swarm. Several specialised sub-agents independently worked the master task below.',
      'Converge their outputs into ONE decisive final answer for the user. Merge the strongest points, resolve conflicts explicitly, drop noise, and keep it tight and actionable. Do not mention the swarm mechanics unless it matters.',
      '',
      `MASTER TASK: ${run.task}`,
      '',
      'SUB-AGENT OUTPUTS:',
      sections,
    ].join('\n')

    const created: any = await client.session.create({ query: { directory: process.cwd() } })
    const sid = created?.data?.id
    if (!sid) throw new Error('could not create synthesis session')
    sessionToSub.set(sid, { runId: run.id, subId: '__synth__' })
    const body: any = { parts: [{ type: 'text', text: prompt }], agent: 'general' }
    if (model) body.model = model
    let summary = ''
    try {
      const res: any = await client.session.prompt({ path: { id: sid }, body })
      const parts = res?.data?.info?.parts ?? res?.data?.parts ?? res?.data ?? []
      summary = extractText(parts)
    } catch (err: any) {
      summary = `⚠️ Synthesis failed: ${err?.message}`
    }
    sessionToSub.delete(sid)
    return summary
  }

  const deploySwarm = async (
    task: string,
    requestedSpread: string[],
    model: { providerID: string; modelID: string } | null
  ): Promise<string> => {
    task = String(task || '').trim()
    if (!task) return 'No task provided.'
    if (swarm && !swarm.endedAt) return 'A swarm is already running. Wait for it to converge or cancel it.'

    const roster = await listAgents()
    const available = roster.map((a) => a.name)
    let spread = requestedSpread.map((s) => String(s)).filter(Boolean)
    if (spread.length === 0) spread = available.slice(0, 3)
    spread = spread.filter((name) => available.length === 0 || available.includes(name))
    if (spread.length === 0) spread = available.length ? [available[0]] : ['general']
    spread = [...new Set(spread)].slice(0, 6)

    const run: SwarmRun = {
      id: `sw${Date.now().toString(36)}${Math.floor(Math.random() * 1e3).toString(36)}`,
      task,
      subs: new Map(),
      summary: null,
      cancelled: false,
      startedAt: Date.now(),
      endedAt: null,
    }
    spread.forEach((role, i) => {
      const id = `a${i + 1}`
      run.subs.set(id, {
        id,
        name: `${role}·${i + 1}`,
        role,
        status: 'pending',
        sessionID: null,
        output: '',
        detail: 'queued',
        startedAt: 0,
        endedAt: null,
      })
    })
    swarm = run

    send({
      type: 'swarm-start',
      id: run.id,
      task,
      agents: [...run.subs.values()].map((s) => ({ id: s.id, name: s.name, role: s.role, status: s.status })),
    })

    // Spread: all sub-agents run in parallel, each in its own session.
    await Promise.all([...run.subs.values()].map((s) => runSubAgent(run, s, model)))

    let summary: string
    if (run.cancelled || cancelledRuns.has(run.id)) {
      summary = 'Swarm cancelled.'
    } else {
      send({ type: 'swarm-update', id: run.id, agentId: '__converge__', status: 'thinking', detail: 'synthesising…' })
      summary = await converge(run, model)
    }
    run.summary = summary
    run.endedAt = Date.now()

    // Tear down routing for every sub session.
    for (const s of run.subs.values()) {
      if (s.sessionID) sessionToSub.delete(s.sessionID)
    }

    send({
      type: 'swarm-converge',
      id: run.id,
      summary,
      agents: [...run.subs.values()].map((s) => ({
        id: s.id,
        name: s.name,
        role: s.role,
        status: s.status,
        output: s.output,
      })),
    })
    send({ type: 'swarm-done', id: run.id, status: run.cancelled ? 'failed' : 'done', summary })
    forward(summary)
    swarmHistory.push(run)
    if (swarmHistory.length > 20) swarmHistory.shift()
    cancelledRuns.delete(run.id)
    swarm = null
    return summary
  }

  const cancelSwarm = (id?: string) => {
    if (!swarm) return
    if (id && swarm.id !== id) return
    swarm.cancelled = true
    cancelledRuns.add(swarm.id)
    for (const s of swarm.subs.values()) {
      if (s.status === 'pending' || s.status === 'running' || s.status === 'thinking') {
        s.status = 'cancelled'
        s.detail = 'cancelled'
        emitUpdate(swarm, s)
      }
    }
  }

  // ---- Connection --------------------------------------------------------
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
          sendConfig()
          return
        }
        if (data.type === 'peer-left') {
          phone = null
        }

        if (data.type === 'get-config' && data.from === 'phone') {
          sendConfig()
          return
        }

        if (data.type === 'model' && data.from === 'phone') {
          const providerID = String(data.providerID || '')
          const modelID = String(data.modelID || '')
          if (providerID && modelID) {
            selectedModel = { providerID, modelID }
            send({ type: 'toast', text: `Model: ${modelID}` })
            send({ type: 'chat', text: `✅ Switched to model **${modelID}** (${providerID}) — applies to the next message.` })
          }
          return
        }

        if (data.type === 'agent' && data.from === 'phone') {
          const name = String(data.agent || '')
          if (name) {
            selectedAgent = name
            send({ type: 'toast', text: `Agent: ${name}` })
            send({ type: 'chat', text: `✅ Switched to agent **${name}** — applies to the next message.` })
          }
          return
        }

        if (data.type === 'chat' && data.from === 'phone') {
          const text = String(data.text || '')
          console.log(`[openbridge] phone: ${text.slice(0, 120)}`)
          await askMain(text)
          return
        }

        if (data.type === 'swarm' && data.from === 'phone') {
          const task = String(data.task || '')
          const spread = Array.isArray(data.spread) ? data.spread.map((s: any) => String(s)) : []
          const model =
            data.model && typeof data.model === 'object' && data.model.providerID
              ? { providerID: String(data.model.providerID), modelID: String(data.model.modelID || '') }
              : selectedModel
          console.log(`[openbridge] swarm: ${task.slice(0, 120)} [${spread.join(', ')}]`)
          deploySwarm(task, spread, model).catch((err: any) => {
            send({ type: 'swarm-done', status: 'failed', summary: `Swarm failed: ${err?.message}` })
          })
          return
        }

        if (data.type === 'swarm-cancel' && data.from === 'phone') {
          cancelSwarm(String(data.id || ''))
          return
        }

        if (data.type === 'status' && data.from === 'phone') {
          console.log(`[openbridge] status: ${String(data.text || '').slice(0, 300)}`)
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
  setTimeout(sendConfig, 1500)
  agent = client

  // ---- Tools -------------------------------------------------------------
  const controlActions = [
    'tap', 'doubleTap', 'longPress', 'swipe', 'scroll', 'key', 'text', 'clearText',
    'launch', 'url', 'back', 'home', 'recents', 'notifications', 'quickSettings',
    'powerDialog', 'lock', 'split', 'wake', 'sleep', 'volume',
  ] as const

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

      phone_control: tool({
        description:
          'Directly control the connected Android phone from OpenBridge: tap, double-tap, long-press, swipe, scroll, press keys, type text, launch apps, open URLs, navigate (home/back/recents), open the notification shade or quick settings, lock/wake the screen, and change volume. Coordinates are fractions (0..1) of the screen.',
        args: {
          action: tool.schema.enum(controlActions as unknown as [string, ...string[]]).describe('the control action to perform'),
          x: tool.schema.number().optional().describe('target x as a fraction 0..1 of screen width'),
          y: tool.schema.number().optional().describe('target y as a fraction 0..1 of screen height'),
          x2: tool.schema.number().optional().describe('end x for swipe'),
          y2: tool.schema.number().optional().describe('end y for swipe'),
          duration: tool.schema.number().optional().describe('gesture duration in ms (swipe / long-press)'),
          keyCode: tool.schema.number().optional().describe('Android keycode for action "key" (e.g. 66 Enter, 4 Back, 3 Home)'),
          key: tool.schema.string().optional().describe('named key for action "key" (e.g. KEYCODE_ENTER)'),
          text: tool.schema.string().optional().describe('text for action "text"'),
          package: tool.schema.string().optional().describe('package name for action "launch"'),
          url: tool.schema.string().optional().describe('URL for action "url"'),
          direction: tool.schema.enum(['up', 'down', 'left', 'right']).optional().describe('scroll direction'),
          stream: tool.schema.string().optional().describe('audio stream for action "volume": music|ring|alarm|notification|system'),
          level: tool.schema.number().optional().describe('absolute level for action "volume"'),
        },
        async execute(args) {
          if (!phone) return 'No phone connected.'
          const payload: Record<string, unknown> = { type: 'control', action: args.action }
          for (const key of ['x', 'y', 'x2', 'y2', 'duration', 'keyCode', 'key', 'text', 'package', 'url', 'direction', 'stream', 'level'] as const) {
            const value = (args as any)[key]
            if (value !== undefined && value !== null) payload[key] = value
          }
          send(payload)
          return `Sent "${args.action}" to the phone.`
        },
      }),

      phone_swarm: tool({
        description:
          'Deploy a swarm: spread one master task across multiple specialised sub-agents (each runs in its own OpenCode session/agent, in parallel), then converge their outputs into a single synthesised answer. Use for research, planning, multi-angle analysis, or any task that benefits from parallel work. Returns the converged result.',
        args: {
          task: tool.schema.string().describe('the master task the swarm should accomplish'),
          spread: tool.schema
            .array(tool.schema.string())
            .optional()
            .describe('agent names to deploy (e.g. ["explore","general","plan"]). Defaults to up to 3 available agents.'),
        },
        async execute(args) {
          if (!phone) return 'No phone connected — the swarm needs the phone UI to stream into.'
          const model = selectedModel
          const summary = await deploySwarm(args.task, args.spread ?? [], model)
          return `Swarm converged.\n\n${summary}`
        },
      }),

      phone_swarm_status: tool({
        description: 'Report the current or most recent OpenBridge swarm and its sub-agents.',
        args: {},
        async execute() {
          const run = swarm ?? swarmHistory[swarmHistory.length - 1]
          if (!run) return 'No swarm has been deployed yet.'
          const lines = [...run.subs.values()].map((s) => `- ${s.name} (${s.role}): ${s.status}${s.detail ? ` — ${s.detail}` : ''}`)
          return [
            `Swarm ${run.id} — ${run.endedAt ? 'finished' : 'running'}`,
            `Task: ${run.task}`,
            ...lines,
            run.summary ? `\nConverged:\n${run.summary}` : '',
          ].join('\n')
        },
      }),
    },

    event: async ({ event }) => {
      const e = event as any
      switch (e.type) {
        case 'session.created': {
          currentSessionID = e.properties?.info?.id || currentSessionID
          if (sessionToSub.size === 0) {
            send({ type: 'chat', text: 'Connected. I can see your phone — ask me anything, or ask me to walk you through a task on your screen.' })
          }
          break
        }
        case 'message.part.updated': {
          const part = e.properties?.part
          const sid = part?.sessionID ?? e.properties?.sessionID
          const route = sid ? sessionToSub.get(sid) : undefined
          if (route) {
            const run = swarm
            if (!run || run.id !== route.runId) break
            const sub = run.subs.get(route.subId)
            if (!sub) break
            if (part?.type === 'thinking' && typeof part.text === 'string' && part.text.trim()) {
              if (sub.status !== 'thinking') {
                sub.status = 'thinking'
                emitUpdate(run, sub)
              }
              sub.detail = part.text.trim().slice(0, 200)
              send({ type: 'swarm-log', id: run.id, agentId: sub.id, line: part.text.trim().slice(0, 400) })
            } else if (part?.type === 'text' && typeof part.text === 'string' && part.text.trim()) {
              sub.output = part.text
              if (sub.status === 'pending') sub.status = 'running'
              emitUpdate(run, sub)
            } else if (part?.type === 'tool' && part.tool) {
              sub.detail = `running ${String(part.tool).slice(0, 60)}`
              emitUpdate(run, sub)
            }
            break
          }
          if (part?.type === 'text' && typeof part.text === 'string' && part.text.trim()) {
            forward(part.text)
          }
          break
        }
        case 'session.idle': {
          const sid = e.properties?.sessionID ?? e.properties?.info?.id
          if (sid && sessionToSub.has(sid)) break
          const alreadySent = lastForwarded != null
          lastForwarded = null
          if (!alreadySent) send({ type: 'chat', text: 'Done.' })
          break
        }
      }
    },
  }
}
