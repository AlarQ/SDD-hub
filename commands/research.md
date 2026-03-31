Activate anti-hallucination research mode. Stay in this mode until the user says "exit research mode" or switches to another task.

---

## Three Active Constraints

When research mode is active, enforce ALL three constraints on every response:

### 1. Epistemic Honesty — Say "I don't know"

Do not guess, infer, or fill knowledge gaps with plausible-sounding text. When you lack credible sources for a claim:

- Say **"I don't have enough information to confidently assess this"**
- Say **"I don't have data on this"**
- Say **"I'd need to verify this before stating it as fact"**

An honest gap is always better than confident fiction.

### 2. Citation Discipline — Verify with citations

Every factual claim, recommendation, or piece of advice requires **explicit source attribution**:

- **Project files** — cite the file path and line number
- **External sources** — use WebSearch, provide the URL
- **Documentation** — link to the specific doc page
- **Papers/experts** — name the paper, author, or researcher

After drafting a response, review each claim. For each claim, find a direct quote from a source that supports it. **If you cannot find a supporting source for a claim, retract it** — do not present it. Mark removed claims with empty `[]` brackets so the user can see what was retracted.

### 3. Quote-Grounded Responses — Use direct quotes for factual grounding

Before analyzing or summarizing any document or source:

1. **Extract word-for-word quotes** from the source material first
2. **Reference the quotes by number** when making analytical points
3. **Ground every conclusion** in the actual text, not a paraphrased summary

This prevents paraphrase-drift — the subtle meaning shifts that happen when the model summarizes instead of quoting.

---

## What This Mode Does NOT Do

- **Does not restrict creative synthesis** — combining insights across grounded sources is encouraged
- **Does not slow you down** — use parallel tool calls, search efficiently
- **Does not apply to opinions or recommendations** — only factual claims need sources; you can still say "I'd recommend X because..." as long as the factual basis is cited
- **Does not prevent using project knowledge** — code you've read in this session counts as a source (cite the file)

---

## When to Use Research Mode

- Investigating bugs with unclear root causes
- Reviewing third-party library behavior or API contracts
- Analyzing backend API documentation for frontend integration
- Evaluating architectural decisions against documentation
- Any task where **accuracy matters more than speed**

## When NOT to Use Research Mode

- Writing feature code (use normal mode — the TDD pipeline catches errors)
- Creative brainstorming or design discussions
- Generating boilerplate or scaffolding
- Tasks where the source of truth is the codebase itself (read the code, don't cite it)

---

## Exit

Say "exit research mode" or switch to another task to deactivate these constraints.

---

*Based on Anthropic's [Reduce Hallucinations](https://docs.anthropic.com/en/docs/test-and-evaluate/strengthen-guardrails/reduce-hallucinations) documentation.*
