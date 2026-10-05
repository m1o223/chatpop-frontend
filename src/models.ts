export const providers = [
  { name: 'Auto', description: 'ChatPop chooses the best AI', symbol: null },
  { name: 'ChatGPT', description: 'OpenAI models', symbol: 'G' },
  { name: 'Claude', description: 'Anthropic models', symbol: 'C' },
  { name: 'Gemini', description: 'Google models', symbol: 'G' },
  { name: 'DeepSeek', description: 'DeepSeek models', symbol: 'D' },
] as const

export type Model = (typeof providers)[number]['name']

// Sections contain arrays so specific model choices can be added under each provider.
export const modelSections = providers.map((provider) => ({
  title: provider.name.toUpperCase(),
  models: [{ ...provider, label: provider.name === 'Auto' ? 'Auto' : `${provider.name} models` }],
}))
