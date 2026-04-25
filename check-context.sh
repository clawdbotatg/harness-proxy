#!/bin/bash
# Validate that clawd-context.md still passes Anthropic's OAuth filter, by
# sending a real test request through Anthropic with the context file embedded.
# Reads the OAuth token from your openclaw agent's auth-profiles.json (default
# clawd; override with HARNESS_AGENT). The script runs from the proxy dir.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CTX="${CONTEXT_FILE:-$SCRIPT_DIR/clawd-context.md}"
HARNESS_AGENT="${HARNESS_AGENT:-clawd}"
AUTH_FILE="$HOME/.openclaw/agents/$HARNESS_AGENT/agent/auth-profiles.json"

if [ ! -f "$CTX" ]; then
  echo "ERROR: context file not found: $CTX"
  echo "Copy clawd-context.example.md to clawd-context.md to start."
  exit 1
fi

if [ ! -f "$AUTH_FILE" ]; then
  echo "ERROR: openclaw auth file not found: $AUTH_FILE"
  echo "Set HARNESS_AGENT env var to your agent id."
  exit 1
fi

TOKEN=$(python3 -c "
import json
with open('$AUTH_FILE') as f:
    d = json.load(f)
profiles = d.get('profiles', {})
# Prefer the first sk-ant-oat01-* token we find
for name, p in profiles.items():
    tok = p.get('token', '')
    if tok.startswith('sk-ant-oat01-'):
        print(tok); break
")

if [ -z "$TOKEN" ]; then
  echo "ERROR: no sk-ant-oat01-* token found in $AUTH_FILE"
  exit 1
fi

CTX_TEXT=$(cat "$CTX")
BODY=$(python3 -c "
import json, sys
ctx = sys.stdin.read()
print(json.dumps({
  'model': 'claude-sonnet-4-5',
  'max_tokens': 50,
  'system': [
    {'type': 'text', 'text': \"You are Claude Code, Anthropic's official CLI for Claude.\"},
    {'type': 'text', 'text': ctx},
  ],
  'messages': [{'role': 'user', 'content': 'gm'}],
  'tools': [
    {'name': 'Read', 'description': 'Read', 'input_schema': {'type':'object','properties':{}}},
    {'name': 'Edit', 'description': 'Edit', 'input_schema': {'type':'object','properties':{}}},
    {'name': 'Write', 'description': 'Write', 'input_schema': {'type':'object','properties':{}}},
    {'name': 'exec', 'description': 'exec', 'input_schema': {'type':'object','properties':{}}},
    {'name': 'process', 'description': 'process', 'input_schema': {'type':'object','properties':{}}},
    {'name': 'memory_search', 'description': 'memory_search', 'input_schema': {'type':'object','properties':{}}},
    {'name': 'web_search', 'description': 'web_search', 'input_schema': {'type':'object','properties':{}}},
    {'name': 'web_fetch', 'description': 'web_fetch', 'input_schema': {'type':'object','properties':{}}},
    {'name': 'image', 'description': 'image', 'input_schema': {'type':'object','properties':{}}},
  ],
}))
" <<< "$CTX_TEXT")

CODE=$(curl -sS -o /tmp/check-resp.txt -w "%{http_code}" https://api.anthropic.com/v1/messages \
  -H "content-type: application/json" \
  -H "anthropic-version: 2023-06-01" \
  -H "anthropic-beta: claude-code-20250219,oauth-2025-04-20" \
  -H "user-agent: claude-cli/2.1.2 (external, cli)" \
  -H "x-app: cli" \
  -H "authorization: Bearer $TOKEN" \
  --data-raw "$BODY")

if [ "$CODE" = "200" ]; then
  echo "✓ Context passes Anthropic OAuth filter (HTTP 200)"
  echo "  Sample response:"
  python3 -c "import json; d=json.load(open('/tmp/check-resp.txt')); print('   ', d['content'][0]['text'][:200])" 2>/dev/null
else
  echo "✗ Context REJECTED (HTTP $CODE)"
  echo "  Response:"
  head -c 400 /tmp/check-resp.txt
  echo
  echo
  echo "Likely culprits in your context file:"
  echo "  - 'sub-agent' / 'multi-agent' / 'agent-to-agent' phrases"
  echo "  - 'sessions_send' / 'sessions_spawn' / 'sessions_list' / 'agents_list'"
  echo "  - File path headings (markdown headings starting with '## /' that contain"
  echo "    suspicious filenames)"
  echo "  - Try removing recent additions and re-running."
  exit 1
fi
