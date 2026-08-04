#!/usr/bin/env bash
# Flags hardcoded 4-byte Solidity function selectors in newly added lines.
# Selectors should be computed at runtime to avoid silent correctness bugs.

FILE=$(jq -r '.tool_input.file_path // empty')

case "$FILE" in
  *.ts|*.sol|*.js) ;;
  *) exit 0 ;;
esac

# For tracked files, check only added lines in the unstaged diff.
# For untracked/new files, check the entire file.
if git ls-files --error-unmatch "$FILE" &>/dev/null; then
  added=$(git diff -- "$FILE" 2>/dev/null | grep '^+' | grep -v '^+++' || true)
else
  added=$(cat "$FILE" 2>/dev/null || true)
fi
[ -z "$added" ] && exit 0

matches=$(echo "$added" | grep -E '\b0x[0-9a-fA-F]{8}\b' || true)

if [ -n "$matches" ]; then
  echo "WARNING: Possible hardcoded 4-byte selector(s) in new code. Compute selectors at runtime instead."
  echo "$matches"
fi

exit 0