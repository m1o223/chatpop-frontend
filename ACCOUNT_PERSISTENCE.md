# Account data integration

The iOS API origin is centralized in `ios/App/App/NativeAPIConfiguration.swift`:
`https://chatpop-backend.onrender.com`. The native authenticated transport uses
HTTPS, does not follow redirects, and keeps credentials in device-only Keychain.
The old LAN Info.plist setting is no longer used by this client.

React calls `accountAPI.ts` through the existing Capacitor plugin. That bridge
allows relative account routes only and never exposes access/refresh tokens to
JavaScript. Web browser preview remains local-only; browser authentication is not
implemented and is not represented as cloud persistence.

On iOS foreground, restore validates `/me` and loads account settings. The web
conversation subscribes to account changes, clears another account's in-memory
data, and loads recent chats. Messages load lazily in pages. The native menu uses
server search and paginated history; long-press a row to rename/delete. New chats
and messages save through the API with retry IDs. No AI reply is simulated.

Theme and selected voice are account preferences while signed in; the local
defaults are only a presentation cache. Keyboard, accessibility, and device
permissions are not uploaded. Display-name changes use `PATCH /me`.

Temporary network errors preserve credentials and last verified profile. A cold
offline launch remains offline, not signed out. Foreground/retry revalidates.
An ambiguous refresh response can still require reauthentication if the server
consumed the token but the rotated response was lost; tokens are not discarded
merely because the network timed out.

Remaining verification: real-iPhone force-quit/reboot, offline recovery, account
switching, reinstall/relogin, and hardware Keychain behavior. Simulator builds and
injected-storage tests do not substitute for those checks.

Cloud binary storage and live generation are not yet configured. Attachment
uploads/media-library UX and stopped assistant response persistence are not claimed.
