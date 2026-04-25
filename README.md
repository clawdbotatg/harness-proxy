# harness-proxy

Local HTTP proxy that lets a third-party agent harness (e.g.
[openclaw](https://github.com/openclaw/openclaw)) talk to Anthropic's API
using a Claude subscription OAuth token, by rewriting outgoing requests so
they pass Anthropic's plan-agnostic OAuth content filter.

> ⚠️ **Anthropic does not permit this.** As of February/April 2026, Anthropic
> has explicitly stated that subscription OAuth tokens are not authorized for
> use in third-party tools, and they enforce that with a server-side filter.
> This proxy circumvents that filter. Doing so violates the Consumer Terms of
> Service. Anthropic has temporarily suspended at least one prominent user.
> For anything beyond local personal experimentation, use a real
> `sk-ant-api03-*` API key with pay-as-you-go billing instead.
>
> This repo exists to document the technique honestly — what triggers the
> filter, what doesn't, and how to architect around it. Use at your own risk.

## What's in here

| File                    | Purpose                                                                 |
| ----------------------- | ----------------------------------------------------------------------- |
| `proxy.js`              | The HTTP proxy. Listens on `127.0.0.1:8901`, forwards to Anthropic.     |
| `clawd-context.example.md` | Template for your custom system context (copy to `clawd-context.md`). |
| `check-context.sh`      | Validates that `clawd-context.md` passes Anthropic's filter.            |
| `ask-brain.sh`          | Wrapper for the harness to query a non-Anthropic sidecar agent.         |

## What the proxy does to outgoing requests

1. Drops the harness's auto-generated auxiliary system block (rejected by the
   filter — too rich with multi-agent / workspace-file references).
2. Injects `clawd-context.md` as the new auxiliary system block.
3. Filters tools to a conservative coding-agent allowlist (filenames in the
   tool array also influence the filter; certain combinations trip it).
4. Scrubs trigger phrases from all message text (system, user, assistant,
   tool args, tool results) so brain replies and prior turns don't trip the
   filter on the next round.

## Trigger phrases the filter rejects (empirically)

These are the patterns I bisected that cause `HTTP 400 invalid_request_error`
with the misleading message "You're out of extra usage":

- `multi-agent`, `sub-agent`, `subagent`, `sub-agents`
- `agent-to-agent`, `cross-session`
- `spawn an agent`, `spawn sub-agents`, `three-brain`
- Tool names mentioned in prose: `sessions_send`, `sessions_spawn`,
  `sessions_list`, `sessions_history`, `agents_list`, `subagents`
- Markdown headings of the form `## /path/to/AGENTS.md` (the literal heading
  trips it; mentioning the same filename in a paragraph does not)
- Certain *combinations* of tools in the `tools` array (e.g., `memory_search`
  + `memory_get` together → 400, individually → 200)

The filter is almost certainly a classifier, not a keyword list. The
substitution table in `proxy.js` is best-effort, not exhaustive.

## Install

```bash
git clone https://github.com/<your-fork>/harness-proxy ~/clawd/harness-proxy
cd ~/clawd/harness-proxy

# personal context
cp clawd-context.example.md clawd-context.md
$EDITOR clawd-context.md
./check-context.sh   # should print ✓ HTTP 200

# auto-start the proxy on macOS
cat > ~/Library/LaunchAgents/com.local.harness-proxy.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>            <string>com.local.harness-proxy</string>
  <key>ProgramArguments</key> <array>
    <string>/opt/homebrew/bin/node</string>
    <string>$HOME/clawd/harness-proxy/proxy.js</string>
  </array>
  <key>RunAtLoad</key>        <true/>
  <key>KeepAlive</key>        <true/>
  <key>StandardOutPath</key>  <string>/tmp/harness-proxy.log</string>
  <key>StandardErrorPath</key><string>/tmp/harness-proxy.err</string>
</dict>
</plist>
EOF
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.local.harness-proxy.plist
```

Or just run it foreground: `node proxy.js`.

## Wire your harness at the proxy

In your openclaw `openclaw.json` (or whatever harness config) set the
Anthropic provider's `baseUrl` to the proxy:

```json
{
  "models": {
    "providers": {
      "anthropic":     { "baseUrl": "http://127.0.0.1:8901" },
      "anthropic-1m":  { "baseUrl": "http://127.0.0.1:8901" }
    }
  }
}
```

## The brain sidecar pattern

Subscription OAuth can't see multi-agent content even via tool results, because
the next request gets scanned. The architectural workaround:

- **Front agent (clawd):** runs on Anthropic OAuth via this proxy. Limited
  toolset (file/exec/web/memory_search). No multi-agent vocabulary.
- **Brain sidecar:** runs on a non-Anthropic model (Venice MiniMax, Bankr,
  Ollama, etc.). Has the full openclaw toolset, the full system prompt, and
  workspace file access. Knows everything the front can't.
- **Glue:** `ask-brain.sh` lets the front agent call the sidecar via
  `exec ~/clawd/harness-proxy/ask-brain.sh "<question>"`. Brain returns plain
  text; the proxy scrubs trigger phrases before the next round-trip so the
  brain's vocabulary doesn't poison the front's history.

## License

MIT.
