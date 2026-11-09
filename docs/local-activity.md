# Local activity indicators

When a local tool is working, Weeklet shows a small pulsing dot and a compact white verb in the menu bar: `think…`, `brew…`, `cook…`, `craft…`, `pond…` or `bake…`. With several active chats, the count stays in front, such as `2 brew…` or `3 craft…`. Chat titles stay in the popover to keep the status item compact. The popover lists up to three titles and a `+N more` line for additional work; the tooltip also includes the first three sanitized titles. When a provider is idle, the extra label disappears. The pulse runs only while a provider is marked active and does not change the status item's width on each frame.

Activity is local and independent of quota requests. It does not add provider API calls, start a CLI, install hooks or change a tool's settings. It uses existing local metadata and transcript lifecycle events. This is a best-effort local signal, not a server-authoritative activity API.

## Sources

**Codex:** reads `CODEX_HOME/state_5.sqlite` through the macOS SQLite library, opened with `SQLITE_OPEN_READONLY` and `query_only`. It selects up to 16 recent, non-archived threads, preferring the explicit `name` over `title`, and reads the corresponding JSONL rollout paths only beneath `CODEX_HOME/sessions`. Subagent rows are excluded so internal helper sessions do not replace the user chat. The query falls back to older title-only columns when needed. No message or preview column is queried. The current schema was inspected on November 9, 2026.

**Claude Code:** inspects up to eight recently changed project directories below `CLAUDE_CONFIG_DIR/projects` and up to 16 recent main-session JSONL files. It prefers explicit `custom-title` records and may use the session index's `summary` title. It never uses `lastPrompt` or `firstPrompt` as a display title and does not scan subagent directories.

The default roots are `~/.codex` and `~/.claude`. The same absolute environment overrides as credential reading apply. Browser chats, remote-only sessions and custom provider stores outside these roots are not tracked.

## Lifecycle signals

Codex `task_started` / `turn_started`, reasoning and tool-call records indicate active work. Completion, abort and final-answer records clear the indicator. Claude user-turn and tool-use records indicate activity; end-turn, duration, stop-hook and cost-state records clear it. Sidechain and meta-user messages are excluded. Unknown records do not supply a title or a made-up status.

Active sessions are counted independently per provider, with duplicate session IDs removed. Titles are ordered by most recent modification. Counts apply to the bounded local sessions being monitored, rather than all cloud activity. A session with no writes for 15 minutes is treated as inactive so an interrupted tool cannot remain marked working forever. A very long silent tool call can therefore lose its indicator before it finishes. A resumed Claude project outside the bounded recent-directory selection may not appear until it becomes recent again. Missing, locked or changed stores simply yield no indicator; quota display continues to work.

## Resource and privacy boundaries

- Activity metadata is checked every five seconds with one second of timer tolerance. Claude's directory candidates are refreshed every 15 seconds.
- Codex's thread index is read only when its database/WAL modification stamp changes.
- Unchanged transcripts are not parsed again. At most the last 256 KiB of a changed owned, regular file is read; final-component symlinks are refused.
- A transcript tail can contain message bytes. Only record types, lifecycle fields, stop reasons and explicit title metadata are inspected for the indicator; message text is not used as a title, shown, logged, saved or sent anywhere.
- Only parsed lifecycle state, a bounded title and file fingerprints are cached in process memory. There is no activity history database or telemetry.
- A separate 0.8-second UI pulse timer exists only during active work. It is invalidated when both providers are idle. Timers do not wake a sleeping Mac.
- Documentation previews use invented `Build interface` and `Review changes` activity titles. Real chat titles are private local UI data and are not committed as fixtures or screenshots.

This implementation was written from observed local field contracts, without copying another app's code. The isolated test suite covers lifecycle transitions, truncation, explicit-title selection, bounded local readers, read-only database contents, stale activity and refresh coalescing.

## Rotating words

The six selected verbs are inspired by Claude Code's documented [spinner verbs](https://code.claude.com/docs/en/settings-reference#spinnerverbs) and the firsthand word list reported in [Anthropic's issue tracker](https://github.com/anthropics/claude-code/issues/61352). They are ambient busy labels, not claims about a tool's current internal operation. No external code or complete word list was copied.

The current label changes about every 6.4 seconds, reusing the existing active-only pulse timer. The two providers use different offsets in the same cycle. Rotation and pulsing stop while idle; no extra timer or network request is added. Words are shortened to four or five letters plus an ellipsis, and activity text is rendered white for contrast. All menu bar text uses the same 11-point font as the percentages.
