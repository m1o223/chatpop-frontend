import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'

const [plistPath, configuration] = process.argv.slice(2)
assert.ok(plistPath && ['Debug', 'Release'].includes(configuration),
  'Usage: node scripts/verify-ios-network-config.mjs <built App.app/Info.plist> Debug|Release')
const plist = JSON.parse(execFileSync('/usr/bin/plutil', ['-convert', 'json', '-o', '-', plistPath], { encoding: 'utf8' }))
const ats = plist.NSAppTransportSecurity
if (configuration === 'Debug') {
  const url = new URL(plist.ChatPopAPIBaseURL)
  assert.ok(!url.hostname.includes('$') && url.hostname !== 'unconfigured.invalid', 'Configure API_HOST before building')
  assert.equal(ats?.NSAllowsArbitraryLoads, undefined, 'Global ATS bypass is not permitted')
  assert.deepEqual(Object.keys(ats?.NSExceptionDomains ?? {}), [url.hostname],
    'The built ATS dictionary key must resolve to the API host, not a literal build-setting placeholder')
  assert.equal(ats.NSExceptionDomains[url.hostname].NSExceptionAllowsInsecureHTTPLoads, true)
  assert.ok(plist.NSLocalNetworkUsageDescription)
} else {
  assert.equal(ats, undefined, 'Release must not contain the development ATS exception')
  assert.equal(plist.NSLocalNetworkUsageDescription, undefined)
  if (plist.ChatPopAPIBaseURL) assert.equal(new URL(plist.ChatPopAPIBaseURL).protocol, 'https:')
}
console.log(`PASS: built ${configuration} API/ATS configuration`)
