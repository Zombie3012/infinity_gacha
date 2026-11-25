# Repository working rules

- Vietnamese if can
- Do not run the full test suite unless the user explicitly requests it. This includes `npm run verify`, root/workspace `npm test`, and equivalent commands that execute all tests.
- When verification is needed for a change, run only relevant targeted checks. Ask before expanding to the full suite.
- Preserve the append-only history in `AGENT_HANDOFF_NOTES.md`.
- Treat `README.md` and the current topic documents in `docs/` as the entry points for current rules; verify implementation in source code and prefer the user's latest decisions if they conflict with older material.
- `AGENT_HANDOFF_NOTES.md`, `docs/design_drafts/`, and dated verification reports are historical context, not proof of current behavior. Do not record routine pull-inspection sessions in the handoff notes.
- `GOAL_QUEUE.md` and discussion files describe proposed future work; reconcile them with current requirements and existing migrations before implementation. Do not treat historical paths or test commands in them as current environment instructions.
