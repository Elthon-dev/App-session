# OpenBridge — Phone control for Opencode

Minimalist web app + Opencode plugin that lets you chat with Opencode from your phone, share your screen, and have Opencode guide you through phone actions step by step.

```
Phone app  ⟷  WebSocket relay  ⟷  Opencode plugin
```

---

## What it does

| Feature | How |
|---|---|
| **Chat** | Text Opencode from your phone in real time |
| **Screen sharing** | Share your phone screen → Opencode sees it |
| **Guided control** | Opencode draws overlays on your phone to tell you exactly where to tap, swipe, or look |
| **Notifications** | Opencode can vibrate your phone and show toasts |
| **Open URLs** | Opencode opens links in your phone browser |

> Direct touch/remote control isn't possible from a web app — instead Opencode gives you visual step-by-step guides so **you** press the right button.

---

## Quick start

### 1. Start the relay server

```bash
cd server
npm install
PORT=8765 node server.js
```

Set `BRIDGE_TOKEN` in production (default `dev-secret-change-me`).

### 2. Add the Opencode plugin

Add to your `.opencode.json` (or `.opencode/opencode.json`):

```json
{
  "plugin": [
    ["./plugin/phone-bridge-plugin.ts", { "env": { "BRIDGE_URL": "ws://127.0.0.1:8765", "BRIDGE_TOKEN": "dev-secret-change-me" } }]
  ]
}
```

Or copy the plugin to `~/.config/opencode/plugins/` for global use and set `BRIDGE_URL` / `BRIDGE_TOKEN` as environment variables before launching Opencode.

### 3. Open the phone app

Either:
- **GitHub Pages**: open your deployed URL, or
- **Local dev**:

```bash
npm run dev
```

Enter your relay URL (e.g. `ws://192.168.1.50:8765`) and tap **Connect**.

---

## Repository structure

```
├── src/                    # Phone web app (React + Vite + Tailwind)
│   ├── components/
│   │   ├── ChatView.jsx
│   │   ├── ConnectionView.jsx
│   │   ├── ScreenShareView.jsx
│   │   ├── GestureOverlay.jsx
│   │   └── StatusBar.jsx
│   ├── hooks/
│   │   └── useScreenCapture.js
│   ├── stores/
│   │   └── appStore.js
│   └── App.jsx
├── server/                 # WebSocket relay (Node + ws)
│   └── server.js
├── plugin/                 # Opencode plugin
│   └── phone-bridge-plugin.ts
├── .github/workflows/      # Deploy to GitHub Pages on push
│   └── deploy.yml
└── vite.config.js
```

---

## Deploying to GitHub Pages

1. Push to GitHub.
2. Enable **Settings → Pages → Source: GitHub Actions**.
3. Every push to `main` deploys the app.

---

## Making the relay reachable from your phone

If running locally, your phone must reach the relay over the LAN.

```bash
# Find your LAN IP
hostname -I

# The relay already listens on 0.0.0.0
# Use ws://<your-ip>:8765 in the phone app
```

If running on a VPS, use `wss://` with a reverse proxy in front for TLS.

---

## Environment variables

| Variable | Used by | Default | Purpose |
|---|---|---|---|
| `PORT` | relay server | `8765` | WebSocket port |
| `BRIDGE_TOKEN` | relay + plugin | `dev-secret-change-me` | shared secret for agent registration |
| `BRIDGE_URL` | plugin | `ws://127.0.0.1:8765` | where plugin finds the relay |

---

## License

MIT