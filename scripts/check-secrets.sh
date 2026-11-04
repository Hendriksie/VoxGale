#!/usr/bin/env bash
# check-secrets.sh — hard gate against committing private data to this public repo.
#
# Modes:
#   --staged (default)  scan the files staged for the next commit   -> pre-commit hook
#   --all               scan every tracked file in the working tree  -> CI
#
# Exit 0 = clean, exit 1 = blocked (hits printed as file:line plus remediation).
#
# Overrides:
#   - inline: put `secret-scan-ignore` on the flagged line
#   - whole file: add the exact repo-relative path to scripts/secret-scan-allowlist.txt
#   - patterns: extend scripts/secret-patterns.txt; false positives go in
#     scripts/secret-scan-exclusions.txt
#
# Never bypass the pre-commit hook with `git commit --no-verify` unless the
# user explicitly instructs it — and if a secret was already pushed, rotate it
# first; removing it from a later commit does not un-leak it.
set -u
cd "$(git rev-parse --show-toplevel)" || { echo "check-secrets: not a git repo" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATTERNS="$SCRIPT_DIR/secret-patterns.txt"
EXCLUSIONS="$SCRIPT_DIR/secret-scan-exclusions.txt"
ALLOWLIST="$SCRIPT_DIR/secret-scan-allowlist.txt"

# grep -f treats every line as a pattern (comments included), so strip
# comment/blank lines into temp files first.
PAT_TMP="$(mktemp)"; EXC_TMP="$(mktemp)"
trap 'rm -f "$PAT_TMP" "$EXC_TMP"' EXIT
grep -v '^[[:space:]]*#' "$PATTERNS" | grep -v '^[[:space:]]*$' > "$PAT_TMP"
grep -v '^[[:space:]]*#' "$EXCLUSIONS" | grep -v '^[[:space:]]*$' > "$EXC_TMP"

MODE="${1:---staged}"
MSG_FILE=""
case "$MODE" in
  --staged) ;;
  --all) ;;
  --msg) MSG_FILE="${2:?--msg needs the message file path}" ;;
  *) echo "usage: check-secrets.sh [--staged|--all|--msg <file>]" >&2; exit 2 ;;
esac

HITS=0
report() { echo "  $1"; HITS=$((HITS + 1)); }

allowlisted() {
  [ -f "$ALLOWLIST" ] && grep -qxF -- "$1" "$ALLOWLIST"
}

# Filename blocklist: files that must never be tracked, whatever their content.
blocked_name() {
  local b
  b="$(basename -- "$1")"
  case "$b" in
    *.example|*.sample|*.template) return 1 ;;           # public templates are fine
    .env|.env.*|.envrc|key.properties|local.properties|google-services.json) return 0 ;;
    id_rsa|id_dsa|id_ecdsa|id_ed25519|.netrc|.npmrc|.pypirc|.git-credentials|.htpasswd) return 0 ;;
    *.jks|*.keystore|*.p12|*.pfx|*.pem|*.keytab|*.mobileprovision) return 0 ;;
    credentials*.json|service-account*.json|service_account*.json) return 0 ;;
  esac
  return 1
}

# stdin: raw pattern hits on one file's content -> stdout: real hits only
filter_hits() {
  grep -ivE -f "$EXC_TMP" | grep -iv 'secret-scan-ignore'
}

# NOTE: every hit must be reported via `report` in the MAIN shell — never from
# inside a pipeline (`... | while read`), because the while then runs in a
# subshell and HITS is lost (bug caught in testing 2026-11-04). Capture hits
# into a variable first, then loop with a here-string.
report_hits() {  # $1 = label prefix (may be empty), $2 = newline-separated raw hits
  local label="$1" raw="$2" h
  [ -z "$raw" ] && return 0
  [ -n "$label" ] && label="$label:"
  while IFS= read -r h; do
    report "$label$h"
  done <<< "$raw"
}

echo "secret-scan ($MODE): scanning ..."

if [ "$MODE" = "--msg" ]; then
  raw=$(grep -inE -f "$PAT_TMP" -- "$MSG_FILE" 2>/dev/null | filter_hits || true)
  report_hits "commit-message" "$raw"
elif [ "$MODE" = "--staged" ]; then
  while IFS= read -r -d '' f; do
    [ -z "$f" ] && continue
    if allowlisted "$f"; then echo "  allowlisted, skipped: $f"; continue; fi
    if blocked_name "$f"; then
      report "BLOCKED FILE NAME staged: $f"
      continue
    fi
    # Skip binary content (numstat shows '-' for added lines); the filename
    # blocklist above already catches the dangerous binary types.
    if [ "$(git diff --cached --numstat -- "$f" | awk '{print $1}')" = "-" ]; then
      continue
    fi
    raw=$(git show ":$f" 2>/dev/null | grep -inE -f "$PAT_TMP" | filter_hits || true)
    report_hits "$f" "$raw"
  done < <(git diff --cached --name-only --diff-filter=ACMR -z)
else
  while IFS= read -r -d '' f; do
    [ -z "$f" ] && continue
    if allowlisted "$f"; then continue; fi
    if blocked_name "$f"; then
      report "BLOCKED FILE NAME tracked: $f"
      continue
    fi
    raw=$(grep -inE -f "$PAT_TMP" -- "$f" 2>/dev/null | sed "s|^|$f:|" | filter_hits || true)
    report_hits "" "$raw"
  done < <(git ls-files -z)
fi

if [ "$HITS" -gt 0 ]; then
  cat >&2 <<'EOF'

SECRET SCAN FAILED — commit/PR blocked. Remediation:
  1. Do NOT commit. If the secret was already pushed, treat it as compromised:
     rotate/revoke it FIRST — removing it in a later commit does not un-leak it.
  2. Remove the data: git rm --cached <file> + .gitignore entry, or replace the
     value with a placeholder.
  3. False positive? Add `secret-scan-ignore` on that line, or list the file in
     scripts/secret-scan-allowlist.txt, and explain why in the commit message.
  4. Do not use `git commit --no-verify` unless explicitly instructed.
EOF
  exit 1
fi
echo "secret-scan ($MODE): clean"
exit 0
