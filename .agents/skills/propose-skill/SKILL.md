---
name: propose-skill
description: Use when a common, repetitive operation is performed in this project (a multi-step task likely to recur, e.g. "again", "like last time") and no existing skill in .claude/skills/ already covers it — propose creating a project-specific skill for it, and create it under .claude/skills/ only after the user explicitly confirms.
---

# Propose a project skill for repetitive work

## When this applies
- You just performed (or are about to perform) an operation in this repo that:
  - has multiple concrete steps beyond a single command, AND
  - is likely to recur (same or similar request expected again), AND
  - isn't already covered by an existing skill in `.claude/skills/`.
- Signals: the user asks for something done before in this project; the task
  is a fixed sequence of steps specific to this repo's conventions (not
  generic engineering advice); the user says things like "again", "like last
  time", "same as before".

## What to do
1. Finish the requested operation first. Do not create a skill silently.
2. Afterward, ask the user whether they want a project skill created for it.
   Describe:
   - A proposed skill name (kebab-case).
   - A one-line description (used for future auto-trigger matching).
   - What the skill would do when invoked.
3. Only on explicit confirmation, create `.claude/skills/<name>/SKILL.md` in
   this repository with:
   - YAML frontmatter: `name`, `description` (specific enough to trigger
     correctly — mention concrete nouns from this project, not generic
     phrasing).
   - A concise body capturing exactly what was done, referencing real file
     paths/commands from this project rather than generic advice.
4. If the user declines, create nothing and don't ask again for that same
   operation unless it recurs.

## What NOT to do
- Don't propose a skill for one-off or trivial operations (a single command,
  nothing repeatable about the structure).
- Don't propose a skill that duplicates one that already exists in
  `.claude/skills/` — check first.
- Don't create the skill file before getting explicit confirmation.
