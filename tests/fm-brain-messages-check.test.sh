#!/usr/bin/env bash
# tests/fm-brain-messages-check.test.sh - the Brain-to-Firstmate wake check
# (bin/fm-brain-messages-check.sh check): silent on a clear and unchanged vault,
# one wake for a new outbox result even with nothing else actionable, silent
# again on the same state, wakes for tracker actions, open questions, and open
# proposals, and never writes into the vault it watches.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

CHECK="$ROOT/bin/fm-brain-messages-check.sh"
TMP_ROOT=$(fm_test_tmproot fm-brain-messages-check-tests)

make_world() {  # <name> -> prints the world dir holding home/, state/, and brain/
  local w="$TMP_ROOT/$1"
  mkdir -p "$w/home" "$w/state" "$w/brain/raw/firstmate/project-tracker" \
    "$w/brain/raw/firstmate/grok-questions/open" "$w/brain/raw/firstmate/grok-outbox" \
    "$w/brain/raw/firstmate/proposals/grpc-account-stream/open"
  printf 'status: clear\n\nNo Firstmate corrections from Brain.\n' > "$w/brain/raw/firstmate/project-tracker/FIRSTMATE-ACTIONS.md"
  printf '%s\n' "$w"
}

check() {  # <world> -> stdout of one check run
  local w=$1
  FM_HOME="$w/home" FM_STATE_OVERRIDE="$w/state" FM_BRAIN_ROOT="$w/brain" "$CHECK" check
}

vault_digest() {  # <world> -> one digest over every vault path with its size and mtime
  (cd "$1/brain" && find . -print0 | sort -z | while IFS= read -r -d '' f; do
    stat -f '%N#%z#%m' "$f" 2>/dev/null || stat -c '%n#%s#%Y' "$f"
  done | cksum)
}

test_clear_vault_is_silent_and_latches() {
  local w out
  w=$(make_world clear)
  out=$(check "$w")
  assert_equals "" "$out" "a clear actions file with no questions, results, or proposals stays silent"
  assert_present "$w/state/.brain-messages" "the first check writes the latch record"
  out=$(check "$w")
  assert_equals "" "$out" "an unchanged clear vault stays silent on the next check"
  pass "clear vault: silent and latched"
}

test_outbox_only_change_wakes_once() {
  local w out
  w=$(make_world outbox)
  check "$w" >/dev/null
  printf -- '---\nid: e2e-1\nstatus: complete\n---\n# Result\n' > "$w/brain/raw/firstmate/grok-outbox/e2e-1.md"
  out=$(check "$w")
  assert_contains "$out" "brain messages: brain outbox/handoff changed" "a new outbox result with nothing else actionable wakes"
  assert_equals 1 "$(printf '%s\n' "$out" | grep -c '^brain messages:')" "exactly one wake line"
  out=$(check "$w")
  assert_equals "" "$out" "the same outbox state stays silent on the next check"
  fm_touch_epoch 1790000000 "$w/brain/raw/firstmate/grok-outbox/e2e-1.md"
  out=$(check "$w")
  assert_contains "$out" "brain outbox/handoff changed" "a changed outbox result wakes again once"
  out=$(check "$w")
  assert_equals "" "$out" "and latches again"
  pass "outbox-only change: wakes once, then silent"
}

test_vault_stays_read_only() {
  local w before after
  w=$(make_world readonly)
  before=$(vault_digest "$w")
  check "$w" >/dev/null
  check "$w" >/dev/null
  after=$(vault_digest "$w")
  assert_equals "$before" "$after" "two checks leave every vault path, size, and mtime unchanged"
  assert_present "$w/state/.brain-messages" "the latch lives in the Firstmate state directory, not the vault"
  pass "vault read-only: the check writes only its own latch under state/"
}

test_actions_questions_and_proposals_still_wake() {
  local w out
  w=$(make_world surfaces)
  check "$w" >/dev/null
  printf 'status: actions\n\n## Close backlog\n\n- id: x\n' > "$w/brain/raw/firstmate/project-tracker/FIRSTMATE-ACTIONS.md"
  out=$(check "$w")
  assert_contains "$out" "FIRSTMATE-ACTIONS close-backlog" "a tracker close action wakes"
  out=$(check "$w")
  assert_equals "" "$out" "the same actions file stays silent afterwards"
  printf '{"id":"q-1","type":"needs-decision"}\n' > "$w/brain/raw/firstmate/grok-questions/open/q-1.json"
  out=$(check "$w")
  assert_contains "$out" "1 grok-questions open" "an open question wakes"
  printf -- '---\nid: prop-1\nstatus: open\n---\n# Why now\n' > "$w/brain/raw/firstmate/proposals/grpc-account-stream/open/prop-1.md"
  out=$(check "$w")
  assert_contains "$out" "1 proposals open" "an open proposal wakes"
  out=$(check "$w")
  assert_equals "" "$out" "unchanged actionable surfaces do not wake twice"
  pass "actions, questions, and proposals: each change wakes once"
}

test_clear_vault_is_silent_and_latches
test_outbox_only_change_wakes_once
test_vault_stays_read_only
test_actions_questions_and_proposals_still_wake
