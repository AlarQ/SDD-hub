# Testing Principles

## Testability
1. **If you can't easily test it, refactor it** — testability is a design signal; untestable code usually has too many responsibilities or hidden dependencies
2. **Pure functions are inherently testable** — same input always produces the same output, no side effects to mock or manage
3. **Isolate side effects** — push I/O, network calls, and state mutations to the edges; keep core logic pure and testable

## Test Structure
4. **Given/When/Then format** — structure tests as: Given (setup/preconditions), When (action under test), Then (assertions/expected outcome)
5. **One assertion concept per test** — each test verifies one behavior; multiple assertions are fine if they verify the same logical outcome
6. **Test behavior, not implementation** — tests should survive refactoring; avoid testing private methods or internal state

## Coverage and Strategy
7. **Test the boundaries** — focus on edge cases, error paths, and integration points rather than happy-path-only coverage
8. **Human names test cases, AI implements bodies** — test case names describe the scenario in plain language; implementation follows from the name
9. **Fast feedback loops** — unit tests should run in seconds; slow tests (integration, e2e) run separately and less frequently
