import { useAppStore } from './stores/appStore'
import StatusBar from './components/StatusBar'
import ConnectionView from './components/ConnectionView'
import ChatView from './components/ChatView'
import ScreenShareView from './components/ScreenShareView'

export default function App() {
  const s = useAppStore()

  const startScreenShare = () => {
    if (!s.streaming) s.setView('screen')
  }

  return (
    <div className="app-shell relative">
      <StatusBar
        state={s.connectionState}
        sessionId={s.sessionId}
        onDisconnect={s.disconnect}
      />

      <main className="flex-1 min-h-0 relative">
        {s.view === 'connection' && (
          <ConnectionView
            onConnect={s.connect}
            serverUrl={s.serverUrl}
            onServerUrlChange={s.setServerUrl}
          />
        )}

        {s.view === 'chat' && (
          <ChatView
            messages={s.messages}
            onSend={s.sendChat}
            onStartScreenShare={startScreenShare}
            connected={s.connectionState === 'connected'}
          />
        )}

        {s.view === 'screen' && (
          <ScreenShareView
            onFrame={s.sendFrame}
            onStop={() => {
              s.setStreaming(false)
              s.setView('chat')
              s.setRemoteControlActive(false)
            }}
            onBackToChat={() => s.setView('chat')}
            remoteControlActive={s.remoteControlActive}
            onRemoteControlChange={s.setRemoteControlActive}
            overlay={s.overlay}
            onOverlayClear={s.clearOverlay}
            onGesture={s.sendGesture}
          />
        )}
      </main>
    </div>
  )
}