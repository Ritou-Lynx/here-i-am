# Device App Blocker via Tasker

Memex does not directly block third-party apps. It acts as the decision layer
and sends a bounded command to a user-configured local executor. On Samsung /
Android, the practical executor is Tasker with Accessibility enabled.

## Memex Side

Open:

`Settings -> Device App Blocker`

Configure:

- Enable Tasker bridge.
- Endpoint: leave empty to use the recommended Tasker Intent bridge.
- Optional shared token: Memex sends it as both `Authorization: Bearer ...` and
  `X-Memex-Token` when using HTTP.
- Default duration: used when the AI locks apps without a more specific user
  request.
- Blocked package names: one per line, for example `com.xingin.xhs`.

The companion agent gets one tool:

`device_app_blocker_control(action, duration_minutes, reason)`

Allowed actions:

- `lock`
- `unlock`
- `status`

When the user explicitly authorizes a focus lock, the agent may call `lock`.
If the bridge is not configured, the tool returns `ok=false` and the agent
must not claim the apps were locked.

## Recommended: Tasker Intent

With an empty endpoint, Memex sends an Android broadcast:

- Intent action: `com.memexlab.hereiam.APP_BLOCKER_COMMAND`
- Extra: `payload_json`

Tasker setup:

1. Create Profile -> Event -> System -> Intent Received.
2. Set Action to `com.memexlab.hereiam.APP_BLOCKER_COMMAND`.
3. In the task, read the `%payload_json` extra.
4. Parse JSON and set:
   - `%MEMEX_BLOCK_MODE = true` when `action == lock`
   - `%MEMEX_BLOCK_UNTIL = until`
   - `%MEMEX_BLOCK_APPS = blocked_packages`
5. If `action == unlock`, set `%MEMEX_BLOCK_MODE = false`.
6. If `action == ping`, do nothing; it is only a connection test.

## Payload

The intent extra, or HTTP POST body when using HTTP, contains JSON:

```json
{
  "action": "lock",
  "block_mode": true,
  "duration_minutes": 45,
  "until": "2026-06-14T01:45:00+08:00",
  "reason": "focus protection",
  "source": "companion_agent",
  "blocked_packages": ["com.xingin.xhs"],
  "timestamp": "2026-06-14T01:00:00+08:00"
}
```

For `unlock`, `block_mode` is `false` and `duration_minutes` / `until` are
`null`. For `ping`, Tasker should leave state unchanged.

## Block Execution Profile

Create another Tasker Profile:

1. Foreground app is one of the blocked packages.
2. In that Profile task, if `%MEMEX_BLOCK_MODE == true`, run `Go Home`, show a
   full-screen scene, or otherwise interrupt the app.
3. Add a timeout check so Tasker clears `%MEMEX_BLOCK_MODE` after
   `%MEMEX_BLOCK_UNTIL`.

## Optional: HTTP Endpoint

If you prefer HTTP, put an `http://...` or `https://...` endpoint into the
settings field. Memex will POST the same JSON body there instead of sending the
Tasker intent.

Recommended Android permissions/settings:

- Enable Tasker Accessibility.
- Exclude Tasker from Samsung battery optimization.
- Keep an emergency unlock path, such as a Tasker quick tile, a special SMS, or
  asking Memex to unlock.

## Safety Boundary

The AI cannot edit the webhook URL, token, app list, or default duration. Those
settings are user-controlled. The AI can only call the already-authorized
bridge with a bounded command.
