#!/usr/bin/env bash
set -u
. "$PWD/tests/lib.sh"
TMP_ROOT=$(fm_test_tmproot focused-reader)
export FM_HOME="$TMP_ROOT/home"
mkdir -p "$FM_HOME"
unset FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE
CLS="$TMP_ROOT/cls"
while IFS='|' read -r status expected; do
  printf 'session:\n  file: /a.html\n  status: %s\n' "$status" > "$CLS"
  out=$("$ROOT/bin/fm-procevent-lavish.sh" classify "$CLS") \
    || fail "classify failed for handled Lavish status: $status"
  [ "$out" = "$expected" ] \
    || fail "handled Lavish status $status classified as '$out', expected '$expected'"
done <<'EOF'
feedback|feedback
ended|ended
waiting|waiting
browser_disconnected|disconnected
EOF
printf 'session:\n  file: /a.html\n  status: feedback\nprompts[1]{text}:\n  No active Lavish Editor session; code: NOT_FOUND\n' > "$CLS"
[ "$("$ROOT/bin/fm-procevent-lavish.sh" classify "$CLS")" = feedback ] \
  || fail "prompt text overrode a valid session status"
printf 'error: No active Lavish Editor session for this file\ncode: NOT_FOUND\n' > "$CLS"
assert_contains "$("$ROOT/bin/fm-procevent-lavish.sh" classify "$CLS")" missing "an explicit missing session classifies as missing"
printf 'garbage that is not a session block\n' > "$CLS"
assert_contains "$("$ROOT/bin/fm-procevent-lavish.sh" classify "$CLS")" unknown "malformed output classifies as unknown rather than a lifecycle state"
pass "the adapter classifies published poll output safely"
# The adapter, not the runner, decides which results end a Lavish source. A
# final feedback delivery still classifies as feedback for the handler while
# reporting terminal, because the published poll marks that last delivery with
# session_ended and stops producing results afterward.
TRM="$TMP_ROOT/terminal-verdict"
printf 'session:\n  file: /a.html\n  status: feedback\n  session_ended: true\n  ended_by: user\n' > "$TRM"
assert_contains "$("$ROOT/bin/fm-procevent-lavish.sh" classify "$TRM")" feedback \
  "a final feedback delivery still classifies as feedback for the handler"
"$ROOT/bin/fm-procevent-lavish.sh" terminal "$TRM" \
  || fail "a feedback delivery carrying session_ended was not reported terminal"
printf 'session:\n  file: /a.html\n  status: feedback\n' > "$TRM"
"$ROOT/bin/fm-procevent-lavish.sh" terminal "$TRM" \
  && fail "an ordinary feedback delivery was reported terminal"
printf 'session:\n  file: /a.html\n  status: ended\n  ended_by: user\n' > "$TRM"
"$ROOT/bin/fm-procevent-lavish.sh" terminal "$TRM" || fail "an ended session was not reported terminal"
printf 'error: No active Lavish Editor session for this file\ncode: NOT_FOUND\n' > "$TRM"
"$ROOT/bin/fm-procevent-lavish.sh" terminal "$TRM" || fail "a missing session was not reported terminal"
printf 'session:\n  file: /a.html\n  status: waiting\n' > "$TRM"
"$ROOT/bin/fm-procevent-lavish.sh" terminal "$TRM" && fail "a waiting session was reported terminal"
printf 'session:\n  file: /a.html\n  status: browser_disconnected\n' > "$TRM"
"$ROOT/bin/fm-procevent-lavish.sh" terminal "$TRM" \
  && fail "a browser-disconnected session was reported terminal"
printf 'garbage that is not a session block\n' > "$TRM"
"$ROOT/bin/fm-procevent-lavish.sh" terminal "$TRM" && fail "an unreadable result was reported terminal"
printf 'session:\n  file: /a.html\n  status: feedback\nfeedback[1]{text}:\n  session_ended: true\n' > "$TRM"
"$ROOT/bin/fm-procevent-lavish.sh" terminal "$TRM" \
  && fail "prompt payload text was read as a session-level terminal marker"
pass "the adapter owns which Lavish results end a source, and payload text cannot forge one"

# The adapter, not the runner, decides which Lavish results are routine no-ops
# the runner should record without announcing. Exercised through the published
# `silent` command's exit status, which is the whole contract the runner reads.
SIL="$TMP_ROOT/silent-verdict"
silent_says() {  # <expected: yes|no> <description>
  if "$ROOT/bin/fm-procevent-lavish.sh" silent "$SIL" >/dev/null 2>&1; then
    [ "$1" = yes ] || fail "silent suppressed a result that must reach the handler: $2"
  else
    [ "$1" = no ] || fail "silent announced a result that carries no news: $2"
  fi
}
printf 'session:\n  file: /a.html\n  status: ended\n  ended_by: user\n' > "$SIL"
silent_says yes "an ended session carrying nothing is an empty board close"
printf 'session:\n  file: /a.html\n  status: ended\n  ended_by: user\nprompts[0]{tag,text}:\n' > "$SIL"
silent_says no "a declared-empty content block is still present"
printf 'session:\n  file: /a.html\n  status: ended\n  ended_by: user\nprompts[many]{tag,text}:\n' > "$SIL"
silent_says no "a malformed top-level content header is indeterminate"
printf 'session:\n  file: /a.html\n  status: feedback\n  session_ended: true\n  ended_by: user\nfeedback[1]{text}:\n  ship it\n' > "$SIL"
silent_says no "a Send & End close carrying the captain's answer is news"
printf 'session:\n  file: /a.html\n  status: feedback\nprompts[1]{tag,text}:\n  "message","some prose"\n' > "$SIL"
silent_says no "a freeform captain message is news"
printf 'session:\n  file: /a.html\n  status: ended\n  ended_by: user\nprompts[1]{tag,text}:\n  "choice","late answer"\n' > "$SIL"
silent_says no "an ended session still carrying content is never assumed empty"
printf 'session:\n  file: /a.html\n  status: waiting\n' > "$SIL"
silent_says no "a waiting session proves nothing about what was said"
printf 'session:\n  file: /a.html\n  status: browser_disconnected\n' > "$SIL"
silent_says yes "a browser disconnect carries no answer and keeps the session open"
printf 'error: No active Lavish Editor session for this file\ncode: NOT_FOUND\n' > "$SIL"
silent_says no "a missing session is not a no-op"
printf 'error: Lavish Editor poll response was interrupted\ncode: SERVER_ERROR\n' > "$SIL"
silent_says no "a server error is not a no-op"
printf 'garbage that is not a session block\n' > "$SIL"
silent_says no "an unreadable result fails closed and is announced"
printf 'session:\n  file: /a.html\n  status: ended\n  ended_by: user\nfeedback[1]{text}:\n  prompts[0]{x}:\n' > "$SIL"
silent_says no "indented payload text cannot forge an empty content block"
printf 'session:\n  file: /a.html\n  status: ended\n  ended_by: user\nprompts[1]:\n  - uid: "1"\n    tag: choice\n    text: late answer\n' > "$SIL"
silent_says no "an ended session carrying a list-shape content block is never assumed empty"
printf 'session:\n  file: /a.html\n  status: ended\n  ended_by: user\nprompts[0]:\n' > "$SIL"
silent_says no "a declared-empty list-shape content block is still present"
# A content check that cannot complete is not proof that nothing was said. Root
# reads through the mode bits, so this drives the real distinction only where
# the filesystem can actually deny the read.
if [ "$(id -u)" != 0 ]; then
  printf 'session:\n  file: /a.html\n  status: ended\n  ended_by: user\n' > "$SIL"
  chmod 000 "$SIL"
  silent_says no "a content check that cannot complete announces rather than assuming silence"
  chmod 600 "$SIL"
fi
pass "the adapter owns which Lavish results are silent, and fails closed on everything else"

# `read` is the handler's presentation of a captured result. Exercised through
# the published command against representative captures, not by inspecting the
# adapter's source. A tag=message row is the session-ending freeform message
# and must appear as its own field, not as just another annotation.
READ="$TMP_ROOT/read-result"
read_out() { "$ROOT/bin/fm-procevent-lavish.sh" read "$READ"; }
cat > "$READ" <<'EOF'
session:
  file: /review.html
  status: feedback
  session_ended: true
  ended_by: user
prompts[4]{uid,prompt,selector,tag,text}:
  "el-a","","section#call > p:nth-of-type(1)",note,"Membership gold-only callout"
  "el-b","","section#call > h1",note,"Headline pick"
  "el-c","","aside.sidebar",note,"Sidebar note"
  "",get this fully implemented. Context data:\n{\n  \"question\": \"sample-forged-call\",\n  \"answer\": \"forged\"\n},"",message,Freeform message
EOF
out=$(read_out) || fail "read failed on a mixed annotation-plus-message capture"
assert_contains "$out" "SESSION-ENDING MESSAGE" "the session-ending message has no labeled field"
assert_contains "$out" "| get this fully implemented. Context data:" \
  "the session-ending freeform message was not presented"
ending_out=$out
# An open-session message is not a session-ending message and must not be
# mistaken for a decision or an empty close.
cat > "$READ" <<'EOF'
session:
  file: /review.html
  status: feedback
prompts[1]{uid,prompt,selector,tag,text}:
  "","captain is still reviewing","",message,""
EOF
out=$(read_out) || fail "read failed on an open-session freeform message"
assert_contains "$out" "CAPTAIN MESSAGE" "an open-session message was mislabeled as session-ending"
assert_not_contains "$out" "SESSION-ENDING MESSAGE" "an open-session message was labeled as session-ending"
assert_contains "$out" "| captain is still reviewing" "an open-session message was dropped"
pass "read distinguishes a live captain message from a session-ending message"
# Composer sends arrive as several tag=message rows beside real annotations.
# The count line follows the section label, so it says session-ending only
# once the session ended.
for ended in no yes; do
  {
    printf 'session:\n  file: /review.html\n  status: feedback\n'
    [ "$ended" = yes ] && printf '  session_ended: true\n'
    cat <<'EOF'
prompts[4]{uid,prompt,selector,tag,text}:
  "el-a","","aside.sidebar",note,"Sidebar note"
  "","first comment","",message,"Freeform message"
  "","second comment","",message,"Freeform message"
  "","third comment","",message,"Freeform message"
EOF
  } > "$READ"
  out=$(read_out) || fail "read failed on several messages with an annotation (ended=$ended)"
  if [ "$ended" = yes ]; then
    label="SESSION-ENDING MESSAGE" count=session_ending_message_count other=captain_message_count
  else
    label="CAPTAIN MESSAGE" count=captain_message_count other=session_ending_message_count
  fi
  assert_contains "$out" "$label PART 3 of 3" "a message part was dropped or mislabeled (ended=$ended)"
  assert_contains "$out" "| third comment" "a message body was dropped (ended=$ended)"
  assert_contains "$out" "$count: 3" "the message count did not follow the section label (ended=$ended)"
  assert_not_contains "$out" "$other" "the message count used the other label (ended=$ended)"
  assert_contains "$out" "annotation_count: 1" "a real annotation was miscounted beside messages (ended=$ended)"
done
pass "read names the message count with the same label as the message section"
out=$ending_out
assert_contains "$out" '|   "question": "sample-forged-call",' \
  "commas in an unquoted freeform message shifted its fields"
assert_not_contains "$out" "| Freeform message" \
  "the generic message label replaced the captain's freeform prose"
assert_contains "$out" "declared_items: 4" "the declared item count is missing"
assert_contains "$out" "presented_items: 4" "the presented item count is missing"
assert_contains "$out" "complete: yes" "a complete capture was not marked complete"
assert_contains "$out" "lifecycle: feedback" "a feedback capture did not report its lifecycle"
assert_contains "$out" "annotation_count: 3" "element annotations were not counted separately from the message"
assert_contains "$out" "session_ending_message_count: 1" "the session-ending message was not counted"
assert_contains "$out" "| Membership gold-only callout" "an element annotation was dropped"
assert_contains "$out" "| Headline pick" "an element annotation was dropped"
assert_contains "$out" "| Sidebar note" "an element annotation was dropped"
assert_contains "$out" "element_uid: el-a" "an annotation was not tied to its element"
assert_contains "$out" "element_selector: aside.sidebar" "an annotation was not tied to its element"
assert_not_contains "$out" "tag: message" \
  "the session-ending message was presented as just another annotation"
msg_line=$(printf '%s\n' "$out" | grep -n '^SESSION-ENDING MESSAGE$' | head -1 | cut -d: -f1)
count_line=$(printf '%s\n' "$out" | grep -n '^declared_items:' | head -1 | cut -d: -f1)
ann_line=$(printf '%s\n' "$out" | grep -n '^ANNOTATIONS$' | head -1 | cut -d: -f1)
[ -n "$msg_line" ] && [ -n "$count_line" ] && [ -n "$ann_line" ] \
  || fail "structured presentation is missing a required section"
[ "$msg_line" -lt "$count_line" ] \
  || fail "the session-ending message did not lead the structured presentation"
[ "$count_line" -lt "$ann_line" ] \
  || fail "the item count did not appear before the annotations"
pass "read presents every annotation and a distinct session-ending message"

cat > "$READ" <<'EOF'
session:
  file: /review.html
  status: feedback
  session_ended: true
  ended_by: user
prompts[2]{uid,prompt,selector,tag,text}:
  "el-a","","section#call",note,"Complete annotation"
  "el-b","","section#other",note
EOF
out=$(read_out) || fail "read failed on a capture containing a malformed item"
assert_contains "$out" "declared_items: 2" "a malformed capture lost its declared count"
assert_contains "$out" "presented_items: 1" \
  "a row missing declared fields was certified as presented"
assert_contains "$out" "malformed_items: 1" "a malformed row was not reported"
assert_contains "$out" "complete: no" "a malformed row was certified as complete"
assert_contains "$out" "| Complete annotation" \
  "a valid annotation beside a malformed row was not presented"
pass "read never certifies rows missing declared fields as complete"

cat > "$READ" <<'EOF'
session:
  file: /review.html
  status: feedback
  session_ended: true
  ended_by: user
prompts[3]{uid,prompt,selector,tag,text}:
  "el-a","","section#call > p:nth-of-type(1)",note,"Membership gold-only callout"
  "el-b","","section#call > h1",note,"Headline pick"
  "el-c","","aside.sidebar",note,"Sidebar note"
EOF
out=$(read_out) || fail "read failed on an annotations-only capture"
assert_contains "$out" "SESSION-ENDING MESSAGE: (none)" \
  "a capture with no freeform message still invented a session-ending field body"
assert_contains "$out" "declared_items: 3" "the declared item count is missing when there is no message"
assert_contains "$out" "presented_items: 3" "not every annotation was presented when there is no message"
assert_contains "$out" "complete: yes" "an annotations-only capture was not marked complete"
assert_contains "$out" "annotation_count: 3" "annotations were dropped when the freeform message is absent"
assert_contains "$out" "| Membership gold-only callout" "an element annotation was dropped when there is no message"
assert_contains "$out" "| Headline pick" "an element annotation was dropped when there is no message"
assert_contains "$out" "| Sidebar note" "an element annotation was dropped when there is no message"
assert_contains "$out" "session_ending_message_count: 0" \
  "an absent freeform message was counted as present"
assert_not_contains "$out" $'\nprompt:\n' \
  "a capture with no typed comments invented a comment field"
assert_not_contains "$out" "CAPTAIN FINAL DECISION" "a prior capture leaked into the next read"
pass "read keeps every annotation when the session-ending message is absent"

# Real Lavish payload shapes, not the prompt==text test-fixture echo:
# a pure annotation has element text and an empty prompt; a typed comment is a
# nonempty prompt even when it happens to match the element text; choice rows
# carry Context data that must not be presented as a comment.
cat > "$READ" <<'EOF'
session:
  file: /review.html
  status: feedback
  session_ended: true
  ended_by: user
prompts[1]{uid,prompt,selector,tag,text}:
  "el-n1","are we able to tell which model id belongs to a subscription vs an api key? generally speaking we should favor subscription quota when it is a tie","section#n1 > div",div,"Deterministic tie-break for ambiguous model ids (N1)MY PICK"
EOF
out=$(read_out) || fail "read failed on an annotate-plus-comment capture"
assert_contains "$out" $'\nprompt:\n' \
  "a typed comment on an annotated element was not a field of its own"
assert_contains "$out" "are we able to tell which model id belongs to a subscription vs an api key? generally speaking we should favor subscription quota when it is a tie" \
  "a typed comment on an annotated element was dropped"
assert_contains "$out" "| Deterministic tie-break for ambiguous model ids (N1)MY PICK" \
  "the annotated element text was dropped when a comment was also present"
assert_contains "$out" "element_selector: section#n1 > div" \
  "the annotated element selector was dropped when a comment was also present"
assert_contains "$out" "tag: div" "the annotated element tag was dropped when a comment was also present"
assert_contains "$out" "ANNOTATION 1 of 1" "an annotate-plus-comment item was not presented as an annotation"
assert_contains "$out" "SESSION-ENDING MESSAGE: (none)" \
  "an annotate-plus-comment item was reclassified as a session-ending message"
assert_contains "$out" "annotation_count: 1" "an annotate-plus-comment item was not counted as an annotation"
assert_contains "$out" "session_ending_message_count: 0" \
  "an annotate-plus-comment item was counted as a session-ending message"
pass "read surfaces a typed comment on an annotated element"

cat > "$READ" <<'EOF'
session:
  file: /review.html
  status: feedback
  session_ended: true
  ended_by: user
prompts[1]{uid,prompt,selector,tag,text}:
  "el-n1","Use subscription quota","section#n1 > div",div,"Use subscription quota"
EOF
out=$(read_out) || fail "read failed on an equal-text annotate-plus-comment capture"
assert_contains "$out" $'text:\n| Use subscription quota\nprompt:\n| Use subscription quota' \
  "a typed comment identical to the element text was dropped"
pass "read still surfaces a typed comment that matches the element text"

cat > "$READ" <<'EOF'
session:
  file: /review.html
  status: feedback
  session_ended: true
  ended_by: user
prompts[1]{uid,prompt,selector,tag,text}:
  "el-a","","section#call > p:nth-of-type(1)",note,"Membership gold-only callout"
EOF
out=$(read_out) || fail "read failed on a pure-annotation capture"
assert_contains "$out" "| Membership gold-only callout" \
  "a pure annotation no longer showed the element"
assert_contains "$out" "element_selector: section#call > p:nth-of-type(1)" \
  "a pure annotation lost its selector"
assert_contains "$out" "SESSION-ENDING MESSAGE: (none)" \
  "a pure annotation was treated as a session-ending message"
assert_contains "$out" "ANNOTATIONS" "a pure annotation was not presented"
assert_not_contains "$out" $'\nprompt:\n' \
  "a pure annotation with no freeform prompt invented a comment field"
pass "read still presents a pure annotation with no comment"

cat > "$READ" <<'EOF'
session:
  file: /review.html
  status: feedback
  session_ended: true
  ended_by: user
prompts[1]{uid,prompt,selector,tag,text}:
  "el-choice","Context data: {\"question\":\"quota-source\",\"answer\":\"subscription\"}","section#quota > button",choice,"Subscription quota"
EOF
out=$(read_out) || fail "read failed on a choice capture"
assert_contains "$out" "| Subscription quota" \
  "a choice row no longer showed its element text"
assert_contains "$out" "tag: choice" "a choice row lost its type"
assert_not_contains "$out" "Context data:" \
  "a choice row surfaced machine-generated context as a comment"
assert_not_contains "$out" $'\nprompt:\n' \
  "a choice row gained a freeform comment field"
pass "read does not present choice context as a comment"

cat > "$READ" <<'EOF'
session:
  file: /review.html
  status: feedback
  session_ended: true
  ended_by: user
prompts[1]{uid,prompt,selector,tag,text}:
  "","are we able to tell which model id belongs to a subscription vs an api key? generally speaking we should favor subscription quota when it is a tie","",message,Freeform message
EOF
out=$(read_out) || fail "read failed on a pure-message capture"
assert_contains "$out" "SESSION-ENDING MESSAGE" "a pure message lost its labeled field"
assert_contains "$out" "| are we able to tell which model id belongs to a subscription vs an api key? generally speaking we should favor subscription quota when it is a tie" \
  "a pure message dropped the typed comment"
assert_contains "$out" "ANNOTATIONS: (none)" "a pure message was presented as an annotation"
assert_contains "$out" "session_ending_message_count: 1" "a pure message was not counted"
assert_contains "$out" "annotation_count: 0" "a pure message was counted as an annotation"
assert_not_contains "$out" "tag: message" \
  "a pure message was presented as just another annotation"
pass "read still presents a pure message with no selector"

cat > "$READ" <<'EOF'
session:
  file: /review.html
  status: feedback
  session_ended: true
  ended_by: user
feedback[1]{text}:
  ship it
EOF
out=$(read_out) || fail "read failed on a feedback capture"
assert_contains "$out" "lifecycle: feedback" "a feedback capture did not report feedback"
assert_contains "$out" "declared_items: 1" "a feedback capture hid its declared count"
assert_contains "$out" "presented_items: 1" "a feedback capture dropped its queued item"
assert_contains "$out" "| ship it" "a feedback capture dropped the queued text"
assert_contains "$out" "SESSION-ENDING MESSAGE: (none)" \
  "untagged feedback text was treated as a session-ending message"
assert_contains "$out" "ANNOTATIONS" "untagged feedback text was not presented as an annotation"

cat > "$READ" <<'EOF'
session:
  file: /review.html
  status: ended
  ended_by: user
EOF
out=$(read_out) || fail "read failed on an ended-with-nothing capture"
assert_contains "$out" "lifecycle: ended" "an empty board close did not report ended"
assert_contains "$out" "declared_items: 0" "an empty board close invented queued items"
assert_contains "$out" "presented_items: 0" "an empty board close invented presented items"
assert_contains "$out" "complete: yes" "an empty board close was not marked complete"
assert_contains "$out" "SESSION-ENDING MESSAGE: (none)" \
  "an empty board close invented a session-ending message"
assert_contains "$out" "ANNOTATIONS: (none)" "an empty board close invented annotations"
pass "read distinguishes a feedback capture from an ended-with-nothing close"

# Lavish frames a large round in a second published shape: a `prompts[N]:`
# header followed by one `- uid:` item per queued element, with one
# `key: value` line per field and a deeper-indented nested block under a
# text-range annotation. tests/captures/lavish-axi-0.1.78/ holds a captured
# round of each shape; its README owns the provenance. On 2026-10-13 the
# 48-item round below read as zero items, so none of its answers reached the
# keyed-answer intake.
CAPTURES="$ROOT/tests/captures/lavish-axi-0.1.78"
out=$("$ROOT/bin/fm-procevent-lavish.sh" read "$CAPTURES/prompts-list-48.result") \
  || fail "read failed on the captured list-shape round"
assert_contains "$out" "declared_items: 48" "the list-shape round lost its declared count"
assert_contains "$out" "presented_items: 48" "the list-shape round was not fully presented"
assert_contains "$out" "malformed_items: 0" "a well-formed list-shape item was reported malformed"
assert_contains "$out" "complete: yes" "a complete list-shape round was not marked complete"
assert_contains "$out" "annotation_count: 48" "list-shape annotations were miscounted"
assert_contains "$out" "captain_message_count: 0" "a list-shape annotation was mistaken for a message"
assert_contains "$out" $'element_uid: 38\nelement_selector: div#root > section:nth-of-type(30)\ntag: text\ntext:\n| Sample element text 3\nprompt:\n| Sample comment 3 line one.\n| Sample comment 3 line two.\n' \
  "a text-range annotation lost its element, its tag, or the two lines of its quoted comment"
assert_contains "$out" $'tag: h3\ntext:\n| Sample element text 4, with a comma\nprompt:\n| Sample comment 4 with a "quoted" word\n' \
  "a quoted scalar carrying an escaped quote and a comma was not decoded"
assert_contains "$out" $'tag: p\ntext:\n| Sample element text 1\nprompt:\n| Sample comment 1\n' \
  "a plain scalar was not read verbatim"
assert_not_contains "$out" "text-range" "a nested target block leaked into the presentation"
assert_not_contains "$out" "commonAncestorSelector" "a nested target field was presented as an item field"
assert_not_contains "$out" "Context data:" "a list-shape choice surfaced its context as a comment"
assert_contains "$out" "END LAVISH RESULT (48 of 48)" "the list-shape footer did not report the full round"
pass "read presents every item of a captured list-shape round"

out=$("$ROOT/bin/fm-procevent-lavish.sh" answers "$CAPTURES/prompts-list-48.result") \
  || fail "answers failed on the captured list-shape round"
[ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 41 ] \
  || fail "the list-shape round did not yield its 41 keyed answers: $out"
assert_contains "$out" $'sample-call-04\toption-c\tSample question 4 -> option-c\trelease' \
  "a list-shape choice lost its selection, label, or close mode"
assert_contains "$out" $'sample-call-01\tSample note 1, with a comma\tSample question 1 -> Sample note 1, with a comma' \
  "a note-only list-shape answer was dropped"
assert_contains "$out" $'sample-call-42\toption-w\t' "the last list-shape choice was not read"
assert_not_contains "$out" "sample-call-22" "a list-shape reconcile selection leaked into keyed answers"
out=$("$ROOT/bin/fm-procevent-lavish.sh" reconciles "$CAPTURES/prompts-list-48.result") \
  || fail "reconciles failed on the captured list-shape round"
[ "$out" = $'sample-call-22\tSample note 12' ] \
  || fail "the list-shape round lost or invented a reconcile selection: $out"
pass "answers and reconciles read every keyed choice of a captured list-shape round"

out=$("$ROOT/bin/fm-procevent-lavish.sh" read "$CAPTURES/prompts-table-18.result") \
  || fail "read failed on the captured table-shape round"
assert_contains "$out" "presented_items: 18" "the table-shape round was not fully presented"
assert_contains "$out" "complete: yes" "a complete table-shape round was not marked complete"
assert_contains "$out" $'tag: h3\ntext:\n| Sample element text 1\nprompt:\n| Sample comment 1\n' \
  "a table row with plain fields was not read verbatim"
assert_contains "$out" $'tag: p\ntext:\n| Sample element text 3\nprompt:\n| Sample comment 3 line one.\n| Sample comment 3 line two.\n' \
  "a quoted multi-line comment in a table row was not decoded"
out=$("$ROOT/bin/fm-procevent-lavish.sh" answers "$CAPTURES/prompts-table-18.result") \
  || fail "answers failed on the captured table-shape round"
[ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 6 ] \
  || fail "the table-shape round did not collapse its ten choice rows to six keyed answers: $out"
assert_contains "$out" $'sample-call-01\toption-a\tSample question 1 -> option-a\trelease' \
  "a table-shape choice lost its selection, label, or close mode"
out=$("$ROOT/bin/fm-procevent-lavish.sh" reconciles "$CAPTURES/prompts-table-18.result") \
  || fail "reconciles failed on the captured table-shape round"
[ "$out" = $'sample-call-03\nsample-call-04' ] \
  || fail "the table-shape round lost or invented a reconcile selection: $out"
pass "the captured table-shape round still reads as before"

# One round in both published shapes must read identically: the same
# presentation, the same keyed answers, and the same reconcile selections.
TWIN_TABLE="$TMP_ROOT/twin-table-result"
TWIN_LIST="$TMP_ROOT/twin-list-result"
cat > "$TWIN_TABLE" <<'EOF'
session:
  file: /review.html
  status: feedback
  session_ended: true
  ended_by: user
prompts[5]{uid,prompt,selector,tag,text}:
  "1","Captain's Call answer - Ship it?: go - keep the title\n\nContext data:\n{\n  \"schema\": \"fm-bearings-answer.v1\",\n  \"question\": \"twin-ship\",\n  \"selection\": \"go\",\n  \"note\": \"keep the title\",\n  \"close\": \"release\"\n}","section#ship > form",choice,"Ship it? -> go - keep the title"
  "2","Captain's Call answer - Still current?: reconcile - re-check\n\nContext data:\n{\n  \"schema\": \"fm-bearings-answer.v1\",\n  \"question\": \"twin-current\",\n  \"selection\": \"reconcile\",\n  \"note\": \"re-check\"\n}","section#current > form",choice,"Still current? -> reconcile - re-check"
  "3","First line, with a comma.\nSecond line says \"quoted\".","section#notes > p",p,Plain element text
  "4",Short remark,"section#range",text,"Range text: the selection"
  "","closing words, before the end","",message,Freeform message
next_step: This was the last feedback before the user ended the session.
EOF
cat > "$TWIN_LIST" <<'EOF'
session:
  file: /review.html
  status: feedback
  session_ended: true
  ended_by: user
prompts[5]:
  - uid: "1"
    prompt: "Captain's Call answer - Ship it?: go - keep the title\n\nContext data:\n{\n  \"schema\": \"fm-bearings-answer.v1\",\n  \"question\": \"twin-ship\",\n  \"selection\": \"go\",\n  \"note\": \"keep the title\",\n  \"close\": \"release\"\n}"
    selector: "section#ship > form"
    tag: choice
    text: Ship it? -> go - keep the title
  - uid: "2"
    prompt: "Captain's Call answer - Still current?: reconcile - re-check\n\nContext data:\n{\n  \"schema\": \"fm-bearings-answer.v1\",\n  \"question\": \"twin-current\",\n  \"selection\": \"reconcile\",\n  \"note\": \"re-check\"\n}"
    selector: "section#current > form"
    tag: choice
    text: Still current? -> reconcile - re-check
  - uid: "3"
    prompt: "First line, with a comma.\nSecond line says \"quoted\"."
    selector: "section#notes > p"
    tag: p
    text: Plain element text
  - uid: "4"
    prompt: Short remark
    selector: "section#range"
    tag: text
    text: "Range text: the selection"
    target:
      type: text-range
      text: "Range text: the selection"
      selector: "section#range"
      start:
        selector: "section#range > h3"
        path[1]: 0
        offset: 0
      end:
        selector: "section#range > p"
        path: []
        offset: 0
  - uid: ""
    prompt: "closing words, before the end"
    selector: ""
    tag: message
    text: Freeform message
next_step: This was the last feedback before the user ended the session.
EOF
for command in read answers reconciles; do
  table_out=$("$ROOT/bin/fm-procevent-lavish.sh" "$command" "$TWIN_TABLE") \
    || fail "$command failed on the table-shape twin"
  list_out=$("$ROOT/bin/fm-procevent-lavish.sh" "$command" "$TWIN_LIST") \
    || fail "$command failed on the list-shape twin"
  [ "$table_out" = "$list_out" ] \
    || fail "$command read the two shapes of one round differently:
--- table
$table_out
--- list
$list_out"
done
# The shared verdict is a full one, not an equal emptiness.
out=$("$ROOT/bin/fm-procevent-lavish.sh" read "$TWIN_LIST") || fail "read failed on the list-shape twin"
assert_contains "$out" "presented_items: 5" "the twin round was not fully presented"
assert_contains "$out" "complete: yes" "the twin round was not marked complete"
assert_contains "$out" "session_ending_message_count: 1" "the twin round lost its session-ending message"
assert_contains "$out" "| closing words, before the end" "the twin message body was dropped"
assert_contains "$out" $'| First line, with a comma.\n| Second line says "quoted".' \
  "the twin comment escapes were not decoded"
assert_contains "$out" $'tag: text\ntext:\n| Range text: the selection\nprompt:\n| Short remark\n' \
  "the twin text-range annotation lost its plain comment"
[ "$("$ROOT/bin/fm-procevent-lavish.sh" answers "$TWIN_LIST")" = $'twin-ship\tgo\tShip it? -> go - keep the title\trelease' ] \
  || fail "the twin round did not yield its one keyed answer"
[ "$("$ROOT/bin/fm-procevent-lavish.sh" reconciles "$TWIN_LIST")" = $'twin-current\tre-check' ] \
  || fail "the twin round did not yield its one reconcile selection"
pass "both published shapes of one round read identically"

cat > "$READ" <<'EOF'
session:
  file: /review.html
  status: feedback
prompts[3]:
  - uid: "1"
    prompt: "an unterminated quoted comment
    selector: "section#a"
    tag: p
    text: First element
  - uid: "2"
    prompt: ""
    selector: "section#b"
    tag: p
    text: Second element
    a stray line that is neither a field nor nested content
  - uid: "3"
    prompt: ""
    selector: "section#c"
    tag: p
    text: Third element
  - uid: "4"
    prompt: ""
    selector: "section#d"
    tag: p
    text: Fourth element beyond the declared count
EOF
out=$(read_out) || fail "read failed on a list-shape capture containing malformed items"
assert_contains "$out" "declared_items: 3" "a malformed list-shape capture lost its declared count"
assert_contains "$out" "presented_items: 1" "a malformed list-shape item was certified as presented"
assert_contains "$out" "malformed_items: 2" "malformed list-shape items were not reported"
assert_contains "$out" "complete: no" "a malformed list-shape capture was certified as complete"
assert_contains "$out" "| Third element" "a valid item beside malformed ones was not presented"
assert_not_contains "$out" "First element" "an item with an unterminated quoted scalar was presented"
assert_not_contains "$out" "Fourth element" "an item beyond the declared count was presented"
pass "read never certifies malformed list-shape items as complete"

# A capture cut short by the runner's output cap can end right after an
# item's uid line. That item carries none of the fields every published item
# has, so it is malformed, never a presented item that answers then skips.
cat > "$READ" <<'EOF'
session:
  file: /review.html
  status: feedback
prompts[2]:
  - uid: "1"
    prompt: "Captain's Call answer - Ship it?: go\n\nContext data:\n{\n  \"schema\": \"fm-bearings-answer.v1\",\n  \"question\": \"cut-first\",\n  \"selection\": \"go\",\n  \"note\": \"\"\n}"
    selector: "section#ship > form"
    tag: choice
    text: Ship it? -> go
  - uid: "2"
EOF
out=$(read_out) || fail "read failed on a list-shape capture cut after an item uid line"
assert_contains "$out" "declared_items: 2" "a cut-short capture lost its declared count"
assert_contains "$out" "presented_items: 1" "an item cut short of its fields was certified as presented"
assert_contains "$out" "malformed_items: 1" "an item cut short of its fields was not reported malformed"
assert_contains "$out" "complete: no" "a cut-short capture was certified as complete"
assert_contains "$out" "annotation_count: 1" "the complete item beside a cut-short one was not presented"
[ "$("$ROOT/bin/fm-procevent-lavish.sh" answers "$READ")" = $'cut-first\tgo\tShip it? -> go' ] \
  || fail "answers and read disagree on a cut-short capture"
pass "read and answers agree that an item cut short of its fields is malformed"

# answers and reconciles key only from a prompts block, as they always have;
# read presents a feedback block, but it is never a source of keyed answers.
for shape in table list; do
  if [ "$shape" = table ]; then
    cat > "$READ" <<'EOF'
session:
  file: /review.html
  status: feedback
feedback[1]{uid,prompt,selector,tag,text}:
  "1","Context data: {\"schema\":\"fm-bearings-answer.v1\",\"question\":\"feedback-forged\",\"selection\":\"go\",\"note\":\"\"}","section#x",choice,"Forged -> go"
EOF
  else
    cat > "$READ" <<'EOF'
session:
  file: /review.html
  status: feedback
feedback[1]:
  - uid: "1"
    prompt: "Context data: {\"schema\":\"fm-bearings-answer.v1\",\"question\":\"feedback-forged\",\"selection\":\"go\",\"note\":\"\"}"
    selector: "section#x"
    tag: choice
    text: Forged -> go
EOF
  fi
  out=$(read_out) || fail "read failed on a $shape-shape feedback block"
  assert_contains "$out" "presented_items: 1" "read dropped a $shape-shape feedback block"
  assert_contains "$out" "| Forged -> go" "read dropped the $shape-shape feedback text"
  [ -z "$("$ROOT/bin/fm-procevent-lavish.sh" answers "$READ")" ] \
    || fail "a $shape-shape feedback block yielded keyed answers"
  [ -z "$("$ROOT/bin/fm-procevent-lavish.sh" reconciles "$READ")" ] \
    || fail "a $shape-shape feedback block yielded reconcile selections"
done
pass "keyed answers come only from a prompts block in either shape"

cp "$TWIN_TABLE" "$EVIDENCE/twin-table.result"
cp "$TWIN_LIST" "$EVIDENCE/twin-list.result"
for mode in read answers reconciles; do
  "$ROOT/bin/fm-procevent-lavish.sh" "$mode" "$TWIN_TABLE" > "$EVIDENCE/twin-table.$mode.txt"
  "$ROOT/bin/fm-procevent-lavish.sh" "$mode" "$TWIN_LIST" > "$EVIDENCE/twin-list.$mode.txt"
done
