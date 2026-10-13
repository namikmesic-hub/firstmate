# Lavish poll result captures

These files contain sanitized stdout from `lavish-axi poll`, captured through `bin/fm-procevent-lavish.sh poll`.
[`../../fm-procevent.test.sh`](../../fm-procevent.test.sh) replays them through `read`, `answers`, and `reconciles`.
Both were captured on 2026-10-13 with `lavish-axi 0.1.78` from one bearings board, over two rounds of the same session.
They are replay inputs for the adapter's result readers, not evidence that a live board was driven in the test.

## Capture provenance

| File | Round | Shape | Items |
| --- | --- | --- | --- |
| `prompts-table-18.result` | first round, 18 queued items | table | 10 choice, 5 p, 2 h3, 1 div |
| `prompts-list-48.result` | second round, 48 queued items | list | 42 choice, 2 h3, 1 p, 1 span, 2 text |

The `lavish_items` comment in [`bin/fm-procevent-lavish.sh`](../../../bin/fm-procevent-lavish.sh) owns the format contract.

## Replay transformations

Every structural byte is unchanged: the session header, the block headers, the field order, the item order, the element uids, selectors, and tags, the nested `target:` block of each text-range annotation, the Context data layout of every choice, and the trailing `next_step` and `dom_snapshot` keys.
The captain's typed notes and comments, the board's question titles, element texts, and answer slugs, the artifact path, and the two trailing scalars were replaced with neutral placeholders, because the originals named colleagues and internal systems.
Each distinct original string maps to one placeholder, so a repeated question keeps one key, a duplicate row stays a duplicate, and a text-range annotation's nested target text still equals its element text.
The substituted files were re-emitted by an encoder whose quoting rule reproduced both originals byte for byte before the substitution: a value is quoted when it is empty, carries a comma, a colon, a quote, a backslash, a brace, a bracket, or a control character, starts or ends with whitespace, starts with a dash, or reads as a number, a boolean, or null.
The placeholders deliberately keep a mix of plain and quoted scalars, a newline inside a comment, and a quote inside a note, so both decoders are exercised on the escapes the real rounds carried.
