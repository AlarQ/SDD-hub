# Scala Code Quality Standards

validation_tools:
  - sbt compile
  - sbt test
  - sbt scalafmtCheck

## Rules

- **Immutability first** — use `val` not `var`; case classes are immutable by default
- **No null** — use `Option[T]` instead; pattern match on `Some`/`None`
- **No exceptions for flow control** — use `Either[E, A]` or `Try` for fallible operations
- **Pattern matching over if-else** — exhaustive matching on sealed traits
- **For-comprehensions for effect composition** — chain `Option`, `Either`, `Future`, `IO`
- **Type classes for polymorphism** — prefer ad-hoc polymorphism over inheritance
- **Sealed traits for ADTs** — compiler ensures exhaustive pattern matching
- **No `return` keyword** — last expression is the return value
- **No `asInstanceOf`** — unsafe casting; use pattern matching instead

## Naming

- **Files**: `PascalCase.scala` (matching the primary type)
- **Packages**: `lowercase.dotted` (com.company.project)
- **Types/Traits/Classes**: `PascalCase`
- **Functions/Variables**: `camelCase`
- **Constants**: `PascalCase` (Scala convention) or `UPPER_SNAKE_CASE`

## Error Handling

```scala
// Option for nullable values
def findUser(id: UUID): Option[User]

// Either for validation with error info
def validateEmail(email: String): Either[String, String]

// For-comprehension chains
val result = for {
  user  <- findUser(userId)
  order <- findOrder(orderId)
} yield (user, order)

// ValidatedNel for accumulating all errors
(validateName(n), validateEmail(e), validateAge(a)).mapN(User.apply)
```

## Collections

- Prefer immutable collections (`List`, `Vector`, `Set`, `Map`)
- Use `Vector` for indexed access, `List` for prepend-heavy workloads
- Use `mutable.ListBuffer` only for building, then `.toList`
- Chain operations: `.filter`, `.map`, `.foldLeft`, `.groupBy`

## Concurrency

- **Futures**: use for-comprehensions; `Future.sequence` for parallel
- **Cats Effect IO**: pure functional effects with `parMapN` for parallelism
- **EitherT**: compose `Either` with `Future`/`IO` via monad transformers

## Project Structure

```
src/main/scala/com/company/project/
├── domain/          # Models (case classes, ADTs), pure business logic
├── application/     # Use cases, application services
├── infrastructure/  # Database, HTTP clients, config
└── interface/       # API controllers, DTOs
```

## Anti-Patterns

- `null` — use `Option`
- `var` — use `val`
- `return` keyword — use expression-based returns
- `asInstanceOf` — use pattern matching
- Exceptions for control flow — use `Either`/`Try`
- Mutable collections in public APIs — return immutable
