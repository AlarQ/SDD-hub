# Architecture Rules

## Composition and Modularity
1. **Composition over inheritance** — build complex behavior by combining simple, focused units rather than deep inheritance hierarchies
2. **Single responsibility per module** — each module/file does one thing well; split when responsibilities diverge
3. **Small modules** — target < 100 lines per module (ideally < 50); extract when a module grows beyond this

## Boundaries and Coupling
4. **Clear interfaces** — modules expose explicit inputs and outputs; no hidden dependencies or implicit shared state
5. **Validate at boundaries** — check data validity at system edges (API handlers, CLI parsers, external integrations); trust internal code
6. **Dependency direction** — depend on abstractions, not concretions; higher-level modules must not depend on lower-level implementation details

## Independence
7. **Independent and composable modules** — modules should be testable, deployable, and understandable in isolation
8. **Explicit dependencies via injection** — pass dependencies as arguments rather than importing globals or singletons
9. **Declarative over imperative** — prefer declarative patterns (map/filter/reduce, configuration-driven) over step-by-step imperative logic where clarity benefits
