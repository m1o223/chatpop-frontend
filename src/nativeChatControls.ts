import { Capacitor, registerPlugin } from '@capacitor/core'
import type { PluginListenerHandle } from '@capacitor/core'
import type { Model } from './models'

export const isNativeIOS = Capacitor.getPlatform() === 'ios'

export type NativeControlEvent =
  | { type: 'appearance'; theme: 'dark' | 'light' | 'system' }
  | { type: 'menu' | 'newChat' }
  | { type: 'model'; model: Model }
  | { type: 'draft'; chatId: string; text: string }
  | { type: 'send'; chatId: string; text: string; messageId: string }
  | { type: 'layout'; top: number; bottom: number }

export type NativeControlState = { chatId: string; draft: string; model: Model; hidden: boolean }

interface NativeChatControlsPlugin {
  accountState(): Promise<{ state: string; userId: string }>
  accountRequest(options: { method: string; path: string; body?: object }): Promise<Record<string, unknown>>
  addListener(event: 'account', callback: (event: { state: string; userId: string }) => void): Promise<PluginListenerHandle>
  showChats(options: { chats: { id: string; title: string }[]; activeId: string }): Promise<{ action: string; selectedId: string }>
  closeChats(): Promise<void>
  configure(state: NativeControlState & { providers: { name: string; description: string }[] }): Promise<{ material: 'liquidGlass' | 'systemMaterial' }>
  updateState(state: NativeControlState): Promise<void>
  hide(): Promise<void>
  addListener(event: 'control', callback: (event: NativeControlEvent) => void): Promise<PluginListenerHandle>
}

export const NativeChatControls = registerPlugin<NativeChatControlsPlugin>('NativeChatControls')
