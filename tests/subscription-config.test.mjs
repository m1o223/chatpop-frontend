import { readFileSync } from 'node:fs'
import assert from 'node:assert/strict'
import test from 'node:test'
const config = JSON.parse(readFileSync(new URL('../public/subscription/plans.json', import.meta.url)))
test('Provider and feature statuses are explicit and supported', () => {
  const items = [...config.providers, ...config.sections.flatMap(section => section.features)]
  for (const item of items) assert.ok(['available', 'comingSoon', 'disabled'].includes(item.status))
  assert.equal(new Set(config.providers.map(p => p.id)).size, config.providers.length)
})
test('No unintegrated AI provider is advertised as live', () => {
  assert.ok(config.providers.every(provider => provider.status !== 'available'))
  assert.deepEqual(config.sections.flatMap(s => s.features).filter(f => f.status === 'available').map(f => f.id), ['dictation'])
})
test('Pricing and credits remain unconfirmed, not invented', () => {
  for (const plan of config.plans) {
    assert.equal(plan.monthlyPrice, null)
    assert.equal(plan.yearlyPrice, null)
    assert.equal(plan.creativeCredits, null)
  }
})
test('Pro includes Plus and planned premium benefits', () => {
  const [plus, pro] = config.plans
  for (const feature of plus.features) assert.ok(pro.features.includes(feature))
  for (const provider of plus.models) assert.ok(pro.models.includes(provider))
  for (const premium of ['videos', 'compare', 'priority']) {
    assert.ok(pro.features.includes(premium))
    assert.ok(!plus.features.includes(premium))
  }
})
test('Plan provider IDs resolve and video analysis stays disabled', () => {
  for (const plan of config.plans) for (const id of plan.models) assert.ok(config.providers.some(p => p.id === id))
  assert.equal(config.sections.flatMap(s => s.features).find(f => f.id === 'videoAnalysis').status, 'disabled')
})
