# CopilotWidget

A macOS menu bar app and desktop widget showing how much of your GitHub Copilot
premium allowance is used this cycle.

The menu bar shows the percentage on its own; the dropdown adds the used/limit line,
plan, an end-of-cycle pace estimate and the reset date.

## The number and its colour

The colour is a coarse signal you can read without opening the menu:

| Used | Colour |
| --- | --- |
| < 80% | green |
| 80–89% | orange |
| 90–94% | red |
| 95%+ | deep purple |

An unlimited plan shows `∞` and no colour.

Usage refreshes every 15 minutes, and on demand via **Refresh Now** (`⌘R`).

## Menu

| Item | |
| --- | --- |
| Refresh Now (`⌘R`) | fetch immediately |
| Import Token from Clipboard | save whatever is on the clipboard as the token |
| Token Settings… (`⌘,`) | paste a token, see connection status, clear it |
| Open at Login | registers the app as a login item (`SMAppService`) |
| Quit (`⌘Q`) | |

**Open at Login** matters more than usual here: the widget only updates while this app is
running, because the app does the fetching (see [Widget](#widget)). macOS may hold a new login
item until it is approved in System Settings → General → Login Items; the app opens that pane
when it does.

## Authentication

The app needs a GitHub token. The simplest is the one the `gh` CLI already holds:

```sh
gh auth token | pbcopy
```

then choose **Import Token from Clipboard** — the token never appears on screen. It is stored
in this app's own Keychain item (service `com.nichelia.CopilotWidget.token`) and is only ever
read by the host app.

A `gho_` token from `gh auth token` is what this was built and tested against. Other kinds
(classic or fine-grained personal access tokens) were **not** tested and may be rejected by
the endpoint below.

A token that is empty, or has whitespace in it, is refused rather than stored. A pasted
`Authorization:`, `Bearer ` or `token ` prefix, or surrounding quotes, is stripped.

## Endpoint

One unofficial call:

```
GET https://api.github.com/copilot_internal/user
Authorization: Bearer <token>
```

It is the endpoint Copilot's editor integrations use. It needs no editor-identifying headers;
only a `User-Agent`, which GitHub requires of any API client. A missing or bad token gets a
`401`, which surfaces as "GitHub rejected the token".

The fields used, from `quota_snapshots.premium_interactions`:

| Field | Used for |
| --- | --- |
| `entitlement` | the limit |
| `quota_remaining` (else `remaining`) | what is left; `used = entitlement − remaining` |
| `percent_remaining`, `credits_used` | fallbacks if the two above are absent |
| `unlimited` | show `∞` instead of a percentage |
| `overage_count` | the overage line |
| `token_based_billing` | whether the unit is labelled "credits" or "requests" |

And from the top level: `copilot_plan` (made readable: `individual_max` → "Individual Max") and
`quota_reset_date_utc` (else `quota_reset_date`).

Only `premium_interactions` has a cap on the plan this was written against; `chat` and
`completions` come back as unlimited. If `premium_interactions` is missing, any other
metered snapshot stands in.

### Choices worth knowing

- **Used is truncated, not rounded.** The true figure can be fractional (`360.7`), and
  GitHub's own `credits_used` is the truncated `360`. Rounding up would show a number one
  higher than GitHub's.
- **The percentage is computed from the quantities** (`used / limit`), so it always agrees with
  the `n / limit` line beside it, rather than taken from `percent_remaining`.
- **The unit is whatever the API says.** GitHub labels the allowance "credits" under
  token-based billing. How that maps to the figure on GitHub's own billing page has not been
  checked.
- **The pace estimate is a straight line**: usage so far, extrapolated to the reset date. The
  cycle is taken to start one calendar month before the reset date — inferred, not reported —
  and no estimate is shown in the first day, when a handful of requests would extrapolate to
  nonsense.

## Caveats

- **This is a private endpoint.** It can change shape or disappear without notice, and nothing
  here is supported by GitHub. Every field is optional and decoded leniently, so a change
  degrades the detail rather than breaking the widget — but if the allowance itself goes
  missing you get "GitHub returned no usage allowance" rather than a number.
- **GitHub's terms of use were not checked** for calling it from a third-party app.
- GitHub documents a supported personal endpoint,
  `GET /users/{username}/settings/billing/premium_request/usage`. It needs the classic `user`
  scope (a `gh` token without it gets a `404`), and it is a usage report, not the allowance.
  It is not used here.
- On a failed refresh the last good reading is kept and shown beside the error.

## Widget

A desktop widget (small: usage ring; medium: ring, plan, used/limit, pace, overage and reset
date) sits beside the menu bar item. The widget extension never touches the network or the
token: the host app fetches, writes the last result to the app-group container
(`snapshot.json`), then asks WidgetKit to reload. If a refresh fails the last good reading is
kept and shown with a "Refresh failed" marker. If the app stops running the widget shows
"Paused" after ~45 minutes.

Add it: right-click the desktop → Edit Widgets → "Copilot Usage".

The widget uses a clear container background so macOS 26's own glass shows through.
`glassEffect` is deliberately not used inside it: a widget is rendered out of process with no
backdrop for the material to sample, and a glassed view draws nothing at all.

## Layout

Same shape as `CursorWidget`, `claude-widget`, `speed-widget` and `scred-widget`: XcodeGen
spec, `App/` + `Shared/` + `Widget/` + `Tools/`. `CopilotWidget.xcodeproj` is generated and
gitignored.

| Path | Role |
| --- | --- |
| `App/CopilotWidgetApp.swift` | `MenuBarExtra` shell and Settings scene |
| `App/CopilotManager.swift` | orchestration, refresh timer, login item, publishes to the widget |
| `App/CopilotAPIClient.swift` | the one endpoint call, and its errors |
| `App/CopilotUsageModels.swift` | lenient decodable response and the parser |
| `App/TokenStore.swift` | Keychain |
| `App/TokenSettingsView.swift` | token entry |
| `Shared/CopilotUsageData.swift` | the model the menu and widget both render, plus the status colour |
| `Shared/SharedStore.swift` | app-group container and the snapshot cache |
| `Widget/` | widget extension: provider and views |
| `Tools/main.swift` | offscreen renderer for the widget views |
| `project.yml` | XcodeGen spec |

Preview without installing:

```sh
swiftc -O Shared/*.swift Widget/Views.swift Widget/Provider.swift Tools/main.swift -o /tmp/render
/tmp/render /tmp   # copilot_<state>_{small,medium}.png, with sample data
```

States rendered: healthy, near the limit, overage, unlimited, failed refresh, paused and no
token.

## Signing and sandbox

Signed with an Apple Development identity via automatic signing. Both targets are sandboxed.

No entitlement here needs a provisioning profile — `network.client` and an app group are not
provisioned on macOS — so the build embeds none. That matters because a free personal Apple
team issues profiles with a 7-day lifetime: when one expires the app stops launching at all
(`launchd job spawn failed`, no crash report) and the widget silently goes blank. If you add a
`keychain-access-groups` entitlement you reintroduce that.

The host app is sandboxed because, unlike the Cursor and Claude widgets, it reads no other
application's credentials.

## Building

Run `xcodegen generate` first, then open `CopilotWidget.xcodeproj` in Xcode and run, or build
and install over the copy in `/Applications` (it can be a login item, so that is the one that
actually runs):

```sh
xcodebuild -project CopilotWidget.xcodeproj -scheme CopilotWidget \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath /tmp/CopilotWidget-rel build
pkill -f "Applications/CopilotWidget"
rm -rf /Applications/CopilotWidget.app
ditto /tmp/CopilotWidget-rel/Build/Products/Release/CopilotWidget.app /Applications/CopilotWidget.app
open /Applications/CopilotWidget.app
```

macOS 26.2 deployment target. `LSUIElement` is set, so there is no Dock icon — the app raises
its activation policy only while the Settings window is open, and drops back on close.

Opening Settings uses the `openSettings` environment action. The
`NSApp.sendAction(Selector(("showSettingsWindow:")))` idiom found in older examples is a
private-selector hack that Apple replaced in macOS 14, and fails silently.

Logs: `log stream --predicate 'subsystem == "com.nichelia.copilotwidget"' --style compact`.
Use `log stream`; these lines do not show up in `log show`.

## History

Earlier versions read a percentage from an Apple Shortcut named "Copilot Usage", run through
`/usr/bin/shortcuts`. That is gone: the app now calls the endpoint directly.
