# Repository working rules

- Do not run the full test suite unless the user explicitly requests it. This includes `npm run verify`, root/workspace `npm test`, and equivalent commands that execute all tests.
- When verification is needed for a change, run only relevant targeted checks. Ask before expanding to the full suite.
- Preserve the append-only history in `AGENT_HANDOFF_NOTES.md`.
