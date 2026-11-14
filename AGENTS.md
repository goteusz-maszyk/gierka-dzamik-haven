# AGENTS.md

## Keep it simple
- Do it as simply as possible. No overcomplicating things.
- Write clean, readable code — a human must be able to read and understand it afterwards without decoding cleverness.
- Prefer the straightforward solution over abstractions, frameworks, or extra layers unless they are clearly needed.

## Config, not hardcoded values
- All tunable values (speeds, timings, frequencies, sizes, colours, counts) live in config files under `config/`.
- Code reads them from config. No magic numbers or tuning constants scattered through scripts.
- A new tunable means a new config entry, never a new hardcoded variable.

## No AI-generated assets
- AI writes code only. Never generate art (sprites, textures, icons) or audio (music, sounds).
- All assets come from the artist. If a feature is blocked on a missing asset, say so — do not fabricate a stand-in.

## No slop
- No filler: no fake or half-done implementations presented as working, no boilerplate, no decorative comments, no speculative features.
- Every line earns its place; if it is not needed, delete it.
- Done means it works end to end and was verified, not "should work".

## Blind reviewers
- After writing or fixing code, run reviewer subagents for code quality and bug hunting before calling it done.
- Reviewers MUST be blind: give them only the code under review and the spec it must satisfy (the relevant DESIGN.md section). Never the conversation, the author's reasoning, or "what I was trying to do".
- The point is fresh eyes: a reviewer that knows the intent rubber-stamps it.

## Don't assume context
- Do not assume context. If something is unclear or missing, ask questions before proceeding.
