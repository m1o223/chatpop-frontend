# Subscription UI configuration

`public/subscription/plans.json` is the single source shared by React and native iOS.
Vite imports it for the web preview; Capacitor sync bundles it under `public/subscription`
for Swift's JSONDecoder. Rebuild and sync after changing it.

- `providers`: id, name, status (`available`, `comingSoon`, `disabled`). Disabled entries are hidden.
- `plans`: id, name, description, badge, model/provider IDs, feature IDs, creativeCredits,
  usageLevel, monthlyPrice and yearlyPrice. Prices are nullable formatted display strings.
- `sections`: heading, side-by-side preference, and features with SF Symbol names and status.
- Null prices display **Coming soon**. Null credits display a plan-specific launch notice.
- Plus/Pro membership is a proposed product configuration, not a server entitlement.
- Dictation is labeled **Available in app**, not paid-only. All AI providers and unconnected
  creation, search, comparison and voice-response features are marked **Coming soon**.
- Pro adds planned video creation, comparison, priority and additional providers; exact
  prices, limits, credit allocations and entitlements still need product approval.

Continue and Restore only show informational notices. There is no StoreKit, billing,
receipt validation or entitlement activation. Legal links use existing placeholder content;
real legal documents are required before offering purchases. Configured prices remain
display-only until a separately approved StoreKit implementation supplies verified products.

Native UI uses UIScrollView, UISegmentedControl, SF Symbols, UIVisualEffectView and the
existing NativeMaterial close control. The purchase area remains reachable and can scroll
internally on compact/large-text layouts. Light appearance uses system colors.
Web styles are isolated to `PaywallScreen.css`; no CSS glass imitation is used.

Run focused config tests with `node --test tests/subscription-config.test.mjs`.
