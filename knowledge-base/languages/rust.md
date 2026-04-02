# Rust Code Quality Standards

validation_tools:
  - cargo clippy -- -D warnings
  - cargo test
  - cargo fmt -- --check

## Rules

- **Leverage ownership** — prevent bugs at compile time; prefer borrowing over cloning
- **No unwrap() in production** — use `Result<T, E>` with `?` operator; `.unwrap()` and `.expect()` are for tests only
- **Domain-specific error types** — use `thiserror` for error enums; one error type per domain
- **Pattern matching over if-else** — use `match`, `if let`, `let else` for exhaustive handling
- **No blocking in async** — use `tokio::task::spawn_blocking` for CPU-bound work in async contexts
- **Repository pattern** — traits in domain/interfaces, implementations in infrastructure
- **Free functions for domain logic** — avoid service structs in the domain layer
- **Layer separation** — handler → domain → repository; never bypass domain logic

## Naming

- **Files**: `snake_case` (transaction_repository.rs)
- **Functions/Variables**: `snake_case` (get_user, user_id)
- **Types/Structs/Traits**: `PascalCase` (Transaction, UserRepository)
- **Constants**: `UPPER_SNAKE_CASE` (MAX_RETRIES)

## Error Handling

```rust
// Use thiserror for domain errors
#[derive(Error, Debug)]
pub enum TransactionError {
    #[error("Database error: {0}")]
    Database(#[from] sqlx::Error),
    #[error("Not found")]
    NotFound,
}

// Propagate with ?
async fn get_transaction(id: Uuid) -> Result<Transaction, TransactionError> {
    sqlx::query_as("SELECT * FROM transactions WHERE id = $1")
        .bind(id)
        .fetch_one(pool)
        .await?
}
```

## Async Patterns

- Use `tokio::spawn` and `JoinSet` for parallel tasks
- Use `tokio::select!` for multiple async sources
- Use `tokio::time::timeout` for deadlines
- Use bounded channels (`mpsc`) for task communication with backpressure

## Anti-Patterns

- `unwrap()` / `expect()` in production code
- `clone()` when borrowing is possible
- Blocking calls (`std::thread::sleep`) in async functions
- Shared mutability — prefer channels or `Arc<Mutex<T>>` sparingly
- Handler calling repository directly — bypasses business logic

## Testing

- Use `#[tokio::test]` for async tests
- Use `#[sqlx::test]` for database tests with real PostgreSQL
- Use `mockall` for mocking external dependencies
- Test behavior, not implementation
- Descriptive test names: `transaction_repository_returns_none_for_nonexistent_id`
- Coverage: critical paths 100%, public APIs 90%+, utilities 80%+
