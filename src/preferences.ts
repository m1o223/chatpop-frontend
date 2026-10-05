export const voices = ['Voice 1', 'Voice 2', 'Voice 3', 'Voice 4'] as const
export type Theme = 'dark' | 'light' | 'system'
export type Preferences = { name: string; voice: string; theme: Theme }
export function readPreferences(): Preferences {
  try {
    const value = JSON.parse(localStorage.getItem('chatpop.preferences') ?? '{}')
    return { name: typeof value.name === 'string' ? value.name.slice(0, 60) : '',
      voice: voices.includes(value.voice) ? value.voice : voices[0],
      theme: ['dark', 'light', 'system'].includes(value.theme) ? value.theme : 'dark' }
  } catch { return { name: '', voice: voices[0], theme: 'dark' } }
}
export function applyTheme(theme: Theme) {
  document.documentElement.dataset.theme = theme
  const light = theme === 'light' || (theme === 'system' && matchMedia('(prefers-color-scheme: light)').matches)
  document.documentElement.dataset.appearance = light ? 'light' : 'dark'
}
export function savePreferences(value: Preferences): boolean {
  applyTheme(value.theme)
  try { localStorage.setItem('chatpop.preferences', JSON.stringify(value)); return true } catch { return false }
}
applyTheme(readPreferences().theme)
matchMedia('(prefers-color-scheme: light)').addEventListener('change', () => {
  if (document.documentElement.dataset.theme === 'system') applyTheme('system')
})
