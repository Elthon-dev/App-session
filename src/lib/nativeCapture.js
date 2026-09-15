import { Capacitor, registerPlugin } from '@capacitor/core'

export const isNative = () => !!(Capacitor && typeof Capacitor.isNativePlatform === 'function' && Capacitor.isNativePlatform())

const ScreenCapture = registerPlugin('ScreenCapture')

export const nativeStartCapture = async (opts = {}) => {
  await ScreenCapture.startCapture({ width: opts.width || 480, height: opts.height || 800 })
}

export const nativeCaptureFrame = async (quality = 35) => {
  const res = await ScreenCapture.captureFrame({ quality })
  return res.data
}

export const nativeStopCapture = async () => {
  try { await ScreenCapture.stopCapture() } catch {}
}