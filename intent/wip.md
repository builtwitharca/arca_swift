---
verblock: "2026-10-18T11:29:06Z:v0.2: matts - ST0001 drafted"
---

# Work In Progress

## Current Focus

**ST0001: Shared Swift libraries for the menu bar apps: Masthead, then LogConsole**

- The design is agreed with hv (18 Oct 2026) and is attached to the thread as design.md.
- Next: WP-01, the package skeleton, its core and CI.
- Then WP-02 and WP-03, ArcaMasthead, followed by its adoptions (WP-04 to WP-07).

## Active Steel Threads

- ST0001: Shared Swift libraries for the menu bar apps: Masthead, then LogConsole

## Upcoming Work

- WP-08: ArcaLogConsole's review, before any of its code.

## Notes

- ic builds the package and adopts it in menuz and Gtools.app. The Intent and Conflab ICs adopt it from ic's brief, in their own repos and under their own gates.

## Context for LLM

This document captures the current state of development on the project. When beginning work with an LLM assistant, start by sharing this document to provide context about what's currently being worked on.

### How to use this document

1. Update the "Current Focus" section with what you're currently working on
2. List active steel threads with their IDs and brief descriptions
3. Keep track of upcoming work items
4. Add any relevant notes that might be helpful for yourself or the LLM
5. Lead each focus item with its thread id in bold, as the placeholders above do, with the thread's digits in place of `####`: the SessionStart hook shows the first such line as the session's `WIP:` line

When starting a new steel thread, describe it here first, then ask the LLM to create the appropriate steel thread document using `intent st new`.
