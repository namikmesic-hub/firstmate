#!/usr/bin/env bash
# fm-brain-messages-check.sh - wake Firstmate when Brain has corrections or results.
#
#   fm-brain-messages-check.sh [check]
#   fm-brain-messages-check.sh arm
#   fm-brain-messages-check.sh disarm
#   fm-brain-messages-check.sh --help
#
# `check` prints one line when Brain surfaces need Firstmate attention, else silent.
# Arm registers state/brain-messages.check.sh with fm-check-register.sh (same trust
# model as tool-updates). Read-only on the vault; Firstmate applies data/ fixes.
set -u
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}}"
STATE="${FM_STATE_OVERRIDE:-$FM_HOME/state}"
BRAIN_ROOT="${FM_BRAIN_ROOT:-$FM_HOME/projects/brain}"
RECORD="$STATE/.brain-messages"
CHECK_ID=brain-messages
CHECK_SHIM="$STATE/$CHECK_ID.check.sh"
CHECK_TRUST="$STATE/$CHECK_ID.check-trust"
REGISTER_BIN="$SCRIPT_DIR/fm-check-register.sh"
UNREGISTER_BIN="$SCRIPT_DIR/fm-check-unregister.sh"
RECORD_SCHEMA=fm-brain-messages-v1
MAX_LINE=220

usage() {
  cat <<'USAGE'
fm-brain-messages-check.sh [check]   report Brain→Firstmate signals (silent when none/new latch)
fm-brain-messages-check.sh arm       write and register state/brain-messages.check.sh
fm-brain-messages-check.sh disarm    remove shim, trust, and latch record
fm-brain-messages-check.sh --help    print this help
USAGE
}

die() { printf 'fm-brain-messages-check: %s\n' "$1" >&2; exit 1; }

cap_line() {
  local s=$1
  if [ "${#s}" -le "$MAX_LINE" ]; then
    printf '%s' "$s"
    return
  fi
  printf '%s…' "${s:0:$((MAX_LINE - 1))}"
}

fingerprint_tree() {
  # Stable fingerprint of watched Brain surfaces.
  local actions="$BRAIN_ROOT/raw/firstmate/project-tracker/FIRSTMATE-ACTIONS.md"
  local open_dir="$BRAIN_ROOT/raw/firstmate/grok-questions/open"
  local out_dir="$BRAIN_ROOT/raw/firstmate/grok-outbox"
  local fp="" part

  if [ -f "$actions" ]; then
    part=$(cksum <"$actions" | awk '{print $1"-"$2}')
    fp="${fp}actions:$part;"
    if grep -q '^status: clear' "$actions" 2>/dev/null; then
      fp="${fp}actions_clear:1;"
    elif grep -qE '^## (Close backlog|Correct captain)' "$actions" 2>/dev/null; then
      fp="${fp}actions_todo:1;"
    fi
  else
    fp="${fp}actions:missing;"
  fi

  local n_open=0
  if [ -d "$open_dir" ]; then
    n_open=$(find "$open_dir" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
  fi
  fp="${fp}open:$n_open;"

  local out_fp=""
  if [ -d "$out_dir" ]; then
    out_fp=$(find "$out_dir" -maxdepth 1 -type f -name '*.md' -print0 2>/dev/null \
      | xargs -0 stat -f '%N#%m' 2>/dev/null | sort | cksum | awk '{print $1"-"$2}')
  fi
  fp="${fp}outbox:${out_fp:-none};"

  local prop_dir="$BRAIN_ROOT/raw/firstmate/proposals"
  local prop_fp="" n_prop=0
  if [ -d "$prop_dir" ]; then
    n_prop=$(find "$prop_dir" -type f -path '*/open/*.md' 2>/dev/null | wc -l | tr -d ' ')
    prop_fp=$(find "$prop_dir" -type f -path '*/open/*.md' -print0 2>/dev/null \
      | xargs -0 stat -f '%N#%m' 2>/dev/null | sort | cksum | awk '{print $1"-"$2}')
  fi
  fp="${fp}proposals:${n_prop}:${prop_fp:-none};"
  printf '%s' "$fp"
}

summarize() {
  local actions="$BRAIN_ROOT/raw/firstmate/project-tracker/FIRSTMATE-ACTIONS.md"
  local open_dir="$BRAIN_ROOT/raw/firstmate/grok-questions/open"
  local parts="" n_open=0

  if [ -f "$actions" ] && ! grep -q '^status: clear' "$actions" 2>/dev/null; then
    if grep -q '^## Close backlog' "$actions" 2>/dev/null; then
      parts="${parts}FIRSTMATE-ACTIONS close-backlog; "
    fi
    if grep -q '^## Correct captain' "$actions" 2>/dev/null; then
      parts="${parts}correct captain/learnings; "
    fi
    if grep -q '^## Other' "$actions" 2>/dev/null; then
      parts="${parts}other actions; "
    fi
  fi

  if [ -d "$open_dir" ]; then
    n_open=$(find "$open_dir" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
  fi
  if [ "$n_open" -gt 0 ]; then
    parts="${parts}${n_open} grok-questions open; "
  fi

  local n_prop=0
  local prop_dir="$BRAIN_ROOT/raw/firstmate/proposals"
  if [ -d "$prop_dir" ]; then
    n_prop=$(find "$prop_dir" -type f -path '*/open/*.md' 2>/dev/null | wc -l | tr -d ' ')
  fi
  if [ "$n_prop" -gt 0 ]; then
    parts="${parts}${n_prop} proposals open; "
  fi

  if [ -n "$parts" ]; then
    printf '%s' "$parts"
  else
    printf '%s' "brain outbox/handoff changed"
  fi
}

record_read() {
  RECORD_FP=""
  [ -f "$RECORD" ] || return 0
  local schema
  schema=$(sed -n '1p' "$RECORD" 2>/dev/null || true)
  [ "$schema" = "$RECORD_SCHEMA" ] || return 0
  RECORD_FP=$(sed -n '2p' "$RECORD" 2>/dev/null || true)
}

record_write() {
  local fp=$1
  mkdir -p "$STATE" || return 1
  local tmp
  tmp=$(mktemp "$STATE/.brain-messages.XXXXXX") || return 1
  printf '%s\n%s\n' "$RECORD_SCHEMA" "$fp" >"$tmp" || { rm -f "$tmp"; return 1; }
  chmod 0600 "$tmp" || { rm -f "$tmp"; return 1; }
  mv -f -- "$tmp" "$RECORD"
}

do_check() {
  [ -d "$BRAIN_ROOT/raw/firstmate" ] || return 0
  local fp findings line
  fp=$(fingerprint_tree)
  record_read
  findings=$(summarize)

  # News if fingerprint changed AND there is something actionable, or open questions, or actions file not clear.
  local actionable=0
  local actions="$BRAIN_ROOT/raw/firstmate/project-tracker/FIRSTMATE-ACTIONS.md"
  local open_dir="$BRAIN_ROOT/raw/firstmate/grok-questions/open"
  local n_open=0
  [ -d "$open_dir" ] && n_open=$(find "$open_dir" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
  if [ "$n_open" -gt 0 ]; then actionable=1; fi
  local n_prop=0
  local prop_dir="$BRAIN_ROOT/raw/firstmate/proposals"
  if [ -d "$prop_dir" ]; then
    n_prop=$(find "$prop_dir" -type f -path '*/open/*.md' 2>/dev/null | wc -l | tr -d ' ')
  fi
  if [ "$n_prop" -gt 0 ]; then actionable=1; fi
  if [ -f "$actions" ] && ! grep -q '^status: clear' "$actions" 2>/dev/null; then
    if grep -qE '^## (Close backlog|Correct captain|Other|Open grok)' "$actions" 2>/dev/null; then
      actionable=1
    fi
  fi

  if [ "$actionable" -eq 0 ]; then
    record_write "$fp" || true
    return 0
  fi

  if [ "$fp" = "$RECORD_FP" ]; then
    return 0
  fi

  line=$(cap_line "brain messages: $findings")
  printf '%s\n' "$line"
  record_write "$fp" || true
  return 0
}

shim_content() {
  local home=$1
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    '# Auto-generated by fm-brain-messages-check.sh' \
    "export FM_HOME=$(printf '%q' "$home")" \
    "exec $(printf '%q' "$SCRIPT_DIR/fm-brain-messages-check.sh") check"
}

do_arm() {
  [ -d "$STATE" ] || die "state directory unavailable"
  [ -x "$REGISTER_BIN" ] || die "fm-check-register.sh missing"
  local tmp
  tmp=$(mktemp "$STATE/.brain-messages-shim.XXXXXX") || die "temp failed"
  shim_content "$FM_HOME" >"$tmp" || { rm -f "$tmp"; die "shim write failed"; }
  chmod 0700 "$tmp" || { rm -f "$tmp"; die "chmod failed"; }
  mv -f -- "$tmp" "$CHECK_SHIM" || die "shim install failed"
  "$REGISTER_BIN" "$CHECK_ID" || die "register failed"
  printf 'armed: state/%s.check.sh (watching %s/raw/firstmate)\n' "$CHECK_ID" "$BRAIN_ROOT"
}

do_disarm() {
  [ -x "$UNREGISTER_BIN" ] && "$UNREGISTER_BIN" "$CHECK_ID" 2>/dev/null || true
  rm -f -- "$CHECK_SHIM" "$CHECK_TRUST" "$RECORD"
  printf 'disarmed: %s\n' "$CHECK_ID"
}

cmd=${1:-check}
case "$cmd" in
  check|"") do_check ;;
  arm) do_arm ;;
  disarm) do_disarm ;;
  --help|-h) usage ;;
  *) usage; exit 2 ;;
esac
