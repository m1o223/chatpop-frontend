# Native Authentication

The existing UIKit screens now call the existing ChatPop backend using native
URLSession. No auth tokens or passwords cross the Capacitor/JavaScript bridge.
The React browser preview, social sign-in buttons and password reset remain
unconnected. No layout redesign or authentication provider SDK was added.

## Development on a real iPhone

1. Connect the Mac and iPhone to the same trusted LAN. Do not use guest Wi-Fi
   with client isolation, a public Wi-Fi network, or Internet port forwarding.
2. In `chatpop-backend`, start PostgreSQL with `node scripts/local-db.mjs start`,
   apply `npm run migrate`, then run `npm run dev:lan:start`. This guarded command
   binds the **API only** to `0.0.0.0:3000` and refuses non-development mode.
   PostgreSQL remains on loopback; database credentials never enter the app.
3. Set `API_HOST` in **`ios/api.local.xcconfig`** to the Mac Wi-Fi IPv4 address
   (`ipconfig getifaddr en0`). This ignored file is already configured on this
   machine. Other machines can use `ios/api.example.xcconfig` as the template.
   `API_BASE_URL = http:/$()/$(API_HOST):3000` composes the central API URL.
   The `$()` escape is necessary because `//` starts an xcconfig comment.
4. Open the existing `ios/App/App.xcodeproj`, select the existing **Debug** App
   scheme/device, and Build & Run. Do not change signing or recreate Capacitor.
5. Allow the iOS Local Network permission. If denied, enable ChatPop in iPhone
   Settings > Privacy & Security > Local Network. Allow the backend through
   the Mac firewall only on the trusted development network. Check
   `http://<MAC_LAN_IP>:3000/health` from iPhone Safari to diagnose reachability;
   Safari success alone does not prove the app has Local Network permission.

`dev:lan:start` keeps the development API running independently of the terminal.
Use `npm run dev:lan:status` to check it and `npm run dev:lan:stop` when finished.
The existing `npm run dev:lan` still runs in the foreground and stops when its
terminal/process stops. Neither command installs a startup service; restart the
database and API after rebooting the Mac. Development API logs are in the
backend's ignored `.local` directory.

The Mac IP can change with Wi-Fi/DHCP. Rebuild the app after changing the xcconfig;
this is native configuration, not a WebView URL. If the coding workspace runs in
a VM or on another computer, its IP is not necessarily the Xcode Mac's Wi-Fi IP.
Run the backend on a host the iPhone can actually reach and configure that host.

## Connection troubleshooting

1. On the backend host, confirm `npm run dev:lan:status` and check both `/health`
   and `/ready` through `http://<MAC_LAN_IP>:3000`. Health tests HTTP reachability;
   readiness also checks PostgreSQL/schema availability.
2. Open that same `/health` URL in **iPhone Safari**. If it fails, the problem is
   server availability or network routing, not auth inputs or Keychain. Check
   that the API host is awake, the devices can reach one another, guest-network
   isolation/VPN is not blocking routing, and port 3000 is permitted. Do not
   disable firewalls globally or expose PostgreSQL to solve this.
3. If Safari succeeds but the app fails, grant ChatPop Local Network access,
   check the Debug build's configured URL, then rebuild the existing app. The
   old installed binary does not pick up xcconfig edits automatically.
4. Debug native logs identify the fixed route, HTTP status or numeric URL error
   code without logging credentials or response bodies. A connection refusal,
   DNS lookup failure, missing network connection, timeout, ATS restriction and
   HTTP server error now have distinct, actionable messages. A timeout alone
   cannot prove whether a firewall, incorrect address or unavailable host caused
   it; the app does not pretend otherwise.

Successful tests from the API host to its own LAN IP **do not verify the phone's
network path**. Complete the iPhone Safari check and native auth checklist before
calling the connection device-verified.

Debug Info.plist preprocessing includes an ATS exception for **only `API_HOST`**
and a Local Network usage description. There is no `NSAllowsArbitraryLoads`,
certificate-trust bypass, global local-network exception, or release HTTP bypass.
Release preprocessing removes the development entries. On iOS 17+ Apple permits
individual IP entries in `NSExceptionDomains`; older supported iOS versions do
not apply ATS to direct-IP requests by default. Actual device behavior still
requires verification with the installed iOS version.

The ATS dictionary key uses the `CHATPOP_API_HOST` C-preprocessor definition,
derived from `API_HOST`. Xcode expands build settings in plist values but left
the original `$(API_HOST)` dictionary key literal in the built app. Always inspect
the built app's `Info.plist`, not just the source plist, when verifying this.
After an Xcode build, check the packaged configuration with
`node scripts/verify-ios-network-config.mjs <built-App.app/Info.plist> Debug`
(or `Release`). This catches unresolved dictionary-key substitutions.

**LAN HTTP is unencrypted. Use test accounts/passwords only.** Production must
use HTTPS. Set the existing App target's Release user-defined **`API_BASE_URL`**
build setting to the real HTTPS origin when it exists. Release has no default
server, does not include `api.local.xcconfig`, and rejects HTTP/local IPv4 URLs.

## Existing API contract

| Route | Native behavior |
| --- | --- |
| `POST /auth/register` | `{email,password}` creates the account; returns `{user}` only |
| `POST /auth/login` | Exchanges email/password for access/refresh credentials |
| `GET /me` | Verifies the session and loads safe account information |
| `POST /auth/refresh` | Exchanges the one-time refresh token; rotates both tokens |
| `POST /auth/logout` | Revokes the current authenticated session |
| `DELETE /me` | `{password,confirmation:"DELETE"}` after native confirmation |

Signup runs register -> login -> /me. Only after verified /me are credentials
committed and Settings updated. A registration whose follow-up login fails
shows an account-created/sign-in-needed message; it does not retry registration.
Signup enforces the backend's 12-128 UTF-16-unit password bounds; login permits
1-128. Password input is cleared on submit, navigation and completion. Passwords
exist only transiently during the request sequence, not in stored app state.

Tokens are a single atomic, nonsynchronizable Keychain item, protected with
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, scoped to the app and bound to
the API origin. They are not in UserDefaults, web storage, URLs or logs. Safe
profile data is kept in memory and fetched again on foreground/Settings entry.
Opening the app restores from Keychain and calls /me; expiring access refreshes
first. Concurrent restores/refreshes coalesce. Refresh is never automatically
retried after an ambiguous response because replay revokes the backend session.
Any refresh failure clears the local session. An offline /me without refresh
retains credentials but hides unverified account state until a later retry.

Sign-out revokes remotely before clearing locally. Offline sign-out reports an
error and retains the session, so it never claims a server revocation happened.
Delete requires password confirmation, uses the existing tested transactional
deletion endpoint, and clears credentials after success. Wrong deletion password
does not sign the user out. Server-side stored-file cleanup remains asynchronous
as documented by the backend. No payments or other Settings features were wired.

## Verification

```sh
# Mac Foundation/Security regression tests, no simulator required:
sh scripts/test-native-auth.sh

# Real HTTP using the production native URLSession client and isolated test storage:
xcrun swiftc -swift-version 5 -D DEBUG -parse-as-library \
  -module-cache-path /tmp/chatpop-auth-cache \
  ios/App/App/NativeAPIConfiguration.swift ios/App/App/NativeAuthSession.swift \
  tests/native/NativeAuthLiveCheck.swift -o /tmp/chatpop-auth-live-check
CHATPOP_AUTH_LIVE_CONFIRM=local-test \
CHATPOP_AUTH_LIVE_BASE_URL="http://<MAC_LAN_IP>:3000" /tmp/chatpop-auth-live-check
```

The live check creates/deletes one uniquely named development account, verifies
registration, duplicate email, wrong password, /me, fresh-client restoration,
refresh, revocation and deletion against the real PostgreSQL-backed API. It
uses volatile test credential storage, **not the iPhone Keychain**. The app's
default initializer always uses Keychain. The backend `npm run verify:auth`
additionally confirms database persistence/hash directly. Tests never truncate
the development database. Do not run the live scripts against production.

The shell defaults to Command Line Tools, but full Xcode was found at
`~/Downloads/Xcode.app`. Use `DEVELOPER_DIR="$HOME/Downloads/Xcode.app/Contents/Developer"`
for Xcode commands without changing the system developer-directory setting.
A signed Debug build and update of the existing iPhone 16 installation succeeded
with the corrected, expanded ATS host. The Release build and packaged-plist
check also passed without a development ATS exception. Signing and Bundle ID
were not changed.
An installed build alone does not verify navigation, Local Network permission,
or Keychain persistence across process termination.

The latest temporary real-device health diagnostic confirmed the phone's Wi-Fi
interface, but did not produce a successful HTTP response before the diagnostic
session ended; no corresponding phone request was observed at the API. The probe
was removed from the final app. Host-side PostgreSQL/auth checks passed, but
real-iPhone health/authentication remains unconfirmed pending the device's
Local Network permission and Safari health check. Do not treat the host-side
checks as a completed real-iPhone authentication test.

On the existing iPhone build, verify Settings -> Sign In -> Sign Up, then force
quit/relaunch, sign out, sign in, wrong password and duplicate email. Repeat
Back/Close while requests are pending and verify no late sign-in or duplicate
views. Check the Xcode console for Auto Layout warnings. Do not call this phase
device-complete until that checklist passes.

Official Apple references:
- [Keychain protection](https://developer.apple.com/documentation/security/ksecattraccessiblewhenunlockedthisdeviceonly)
- [Local network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)
- [ATS local/IP behavior](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking)
