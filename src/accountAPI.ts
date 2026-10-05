import { isNativeIOS, NativeChatControls } from './nativeChatControls'

export type CloudChat = { id: string; title: string }
export type CloudMessage = { id: string; content: string; role: 'user' | 'assistant' | 'system' }

// iOS owns the transport and Keychain. No bearer/refresh credentials cross this bridge.
export async function accountRequest<T>(method: string, path: string, body?: object): Promise<T> {
  if (!isNativeIOS) throw new Error('Sign in using the ChatPop iOS app to sync your account.')
  return await NativeChatControls.accountRequest({ method, path, body }) as T
}

export async function listChats(offset = 0) {
  return accountRequest<{ chats: CloudChat[] }>('GET', `/chats?limit=50&offset=${offset}`)
}

export async function listMessages(chatId: string, offset = 0) {
  return accountRequest<{ messages: CloudMessage[] }>('GET', `/chats/${chatId}/messages?limit=50&offset=${offset}`)
}
