---
name: code-comments
description: General-purpose guidance for writing clear, concise comments in any programming language — when to comment, what to avoid, and consistent style for header, block, and inline comments. Use whenever writing new code, reviewing code, or asked to "add comments," "clean up comments," "document this function," or improve readability of existing code through commentary. Trigger this for any language, not just one — it covers the judgment calls (what's worth commenting, what isn't) as well as formatting (lowercase, short inline notes beside specific lines).
---

# Code Comments

Guidance for writing comments that are worth reading: present when needed, silent when not, and never just a restatement of the code in English.

## Core Principle: Comment the Why, Not the What

The code already says *what* it does — that's what reading the code is for. A comment earns its place only when it adds something the code can't say on its own:
- **Why** this approach and not an obvious alternative.
- **Intent** behind a non-obvious value, threshold, or edge case.
- **Context** that lives outside the file — a spec section, a hardware quirk, a bug this works around.
- **Warning** about something fragile, order-dependent, or easy to break by "cleaning up."

If a comment would just translate the line into English (`i = i + 1; // increment i`), delete it. The bar is: would a competent reader of this language need this comment, or are they being told something they could already see?

## Style: Lowercase, Short, Beside the Line

This applies across all comment types unless a language's own convention overrides it (e.g. doc-comment tools like Javadoc/JSDoc that parse a specific casing or tag format — match the tool's required format there, lowercase everything else around it).

- All lowercase. No capitalized first word, no terminal period, on inline and most block comments.
- Inline comments beside specific lines should be short — a few words, not a sentence. They're a label, not an explanation: `x <= a + b; // accumulate partial sum`, not `x <= a + b; // this line adds a and b together and stores the result in x`.
- Put the inline comment on the same line as the code it annotates whenever the line length allows it. Only move to a comment on the line above when the inline version would push the line over a reasonable width or when annotating a multi-line statement.
- Don't pad comments with extra spaces to align them in a column down the file. Alignment looks tidy for one commit and then drifts out of sync the moment any line's length changes, at which point it's worse than no alignment.

## What Deserves a Comment

- **Non-obvious "why."** A magic-looking number, a workaround, an algorithm choice — anything where a reader's next question would be "why this and not the obvious thing."
- **Boundary and edge-case handling.** A check that exists only because of one specific edge case is invisible without a note saying which case it's for.
- **Anything that looks deletable but isn't.** If removing a line looks safe but would reintroduce a bug, say so — this is the single highest-value comment type, because it prevents future regressions directly.
- **Section headers in long functions/files**, to help a reader skim structure before reading line by line — but only once the function/file is long enough that skimming is actually useful; don't header-ize a 10-line function.
- **Public/external interfaces** (function signatures other code or other people call) — even a one-line summary of what it does and any non-obvious parameter meaning, since the caller may never read the implementation.

## What Doesn't Deserve a Comment

- Anything the code already states clearly through naming. Good names are cheaper to maintain than comments and can't go stale.
- Restating control flow in English (`// loop through the list`, `// return early if empty`).
- Comments that exist because the surrounding code is unclear — fix the code (better names, extracted helper, simplified logic) instead of explaining around it. A comment is a patch, not a fix, for unreadable code.
- Commented-out code left "just in case." Delete it — version control is the safety net, not a comment block.
- Changelog-style comments inside the function (`// added by X on date — fixed bug Y`). That's what commit history and blame are for; a comment like this goes stale immediately and clutters every future reader.

## Header / Block Comment Structure

When a function, module, class, or file needs more than a one-line note:

- Keep it short — a sentence or two on purpose, plus parameters/returns only when their meaning isn't obvious from name and type alone. Don't restate every parameter mechanically if the names are already self-explanatory; only annotate the ones with a non-obvious meaning, range, or unit.
- One consistent header shape per file/project. Pick a block-comment style appropriate to the language and don't mix two styles in the same file (e.g. don't mix `/** ... */` and `// ...` banner blocks for the same kind of header).
- For files/modules: a short comment at the top stating purpose is enough. Skip elaborate ASCII-art banner headers — they take real estate and go stale the moment the file's role changes, since nobody updates the banner art.

## Density Check

- If a function has no comments and isn't obvious from naming alone, it's under-commented — flag the non-obvious parts.
- If nearly every line has an inline comment, it's over-commented — comments at that density usually mean either the code needs simplifying, or most of those comments are restating the line rather than adding something. Keep the few that explain genuine "why," drop the rest.
- A good rough check while reviewing: cover the comments and read just the code. Anywhere you'd genuinely have a question a comment should answer it — anywhere you wouldn't, the comment is probably dead weight.

## When Asked to "Add Comments" to Existing Code

- Read the code fully first. Identify the genuinely non-obvious parts (the why, the edge cases, the fragile bits) before writing anything.
- Don't comment every line by default just because the request was "add comments" — apply the same what-deserves-a-comment filter above. A request for more comments means "make this easier to understand," not "annotate every statement."
- Match existing project style if the file already has a consistent convention, even if it differs slightly from the defaults here — consistency within a file/project beats imposing a different house style line by line.