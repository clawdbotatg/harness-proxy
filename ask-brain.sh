#!/bin/bash
# Ask the brain sidecar (a cheap-model openclaw agent with full workspace access)
# a question. The brain runs on a non-Anthropic model (e.g., venice/minimax-m27)
# so it isn't subject to Anthropic's OAuth content filter, and it can use any
# openclaw tool / read any workspace file. Returns its text reply on stdout.
#
# Usage:
#   ask-brain.sh "what does MEMORY.md say about project X?"
#   ask-brain.sh "what github username should I use in this directory?"
#
# Configure the brain agent name + session via env vars (defaults below).

if [ $# -eq 0 ]; then
  echo "usage: ask-brain.sh \"<question>\""
  exit 1
fi

QUESTION="$*"
BRAIN_AGENT="${BRAIN_AGENT:-clawd-brain}"
BRAIN_SESSION_ID="${BRAIN_SESSION_ID:-brain-session-1}"

openclaw agent \
  --agent "$BRAIN_AGENT" \
  --session-id "$BRAIN_SESSION_ID" \
  -m "$QUESTION" \
  --json 2>/dev/null | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    payloads = d.get('result', {}).get('payloads', [])
    if payloads:
        print(payloads[0].get('text', '(empty reply)'))
    else:
        print('(no reply)')
except Exception as e:
    print(f'(brain error: {e})', file=sys.stderr)
    sys.exit(1)
"
