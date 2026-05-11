---
id: "003"
name: "Parser cache + markdown sanitizer + cold scanner"
status: blocked
blocked_by: ["002"]
max_files: 12
estimated_files:
  - workflow-web/src/cache.rs
  - workflow-web/src/sanitize.rs
  - workflow-web/src/scanner.rs
  - workflow-web/src/limits.rs
  - workflow-web/src/error.rs
  - workflow-web/tests/cache_test.rs
  - workflow-web/tests/sanitize_test.rs
  - workflow-web/tests/scanner_test.rs
  - workflow-web/tests/fixtures/xss/script.md
  - workflow-web/tests/fixtures/xss/onerror.md
  - workflow-web/tests/fixtures/xss/data_uri.md
  - workflow-web/tests/fixtures/large/huge.md
test_cases:
  - "sanitize strips <script> tags"
  - "sanitize strips on* event handler attrs"
  - "sanitize strips javascript: URLs in href"
  - "sanitize strips author-supplied vscode: URLs"
  - "sanitize strips data: URLs"
  - "sanitize allowlist matches SEC-FR-8 (tags, attrs, schemes)"
  - "cache hit returns same CacheEntry for unchanged (mtime, len)"
  - "cache miss after mtime change forces reparse and re-sanitize"
  - "cache miss after len change forces reparse (mtime granularity defense)"
  - "cache.invalidate(path) removes the entry"
  - "cache sweep removes paths that no longer exist on disk"
  - "scanner walks projects/*/specs/** and populates cache"
  - "scanner cold-scan of 100-spec fixture completes < 500ms (target, advisory)"
  - "files > 2 MiB produce CoreError::TooLarge { limit: 2097152 }"
  - "mermaid block source > 16 KiB is rejected/capped (SEC-FR-11)"
  - "AppState::new(config) runs cold scan and populates cache before serve"
ground_rules:
  - general:security/general.md
  - general:architecture/general.md
  - general:languages/rust/concurrency.md
  - general:languages/rust/ownership.md
  - general:languages/rust/error-handling.md
  - general:testing/principles.md
  - project:languages/rust.md
---

## Description

Implement sanitization pipeline (`pulldown-cmark` → `ammonia`), `DashMap`-backed cache keyed `(mtime, len)`, cold scanner. Wired into `AppState`. No HTTP routes yet — everything reachable through unit + integration tests on the cache+sanitizer surface. Implements ADR-003 + ADR-008.

## Public API

- `sanitize::render(markdown: &str) -> Result<String, CoreError>` — single sanitized-HTML sink.
- `Cache::get_or_load(path: &Path) -> Result<Arc<CacheEntry>, CoreError>` — stat, compare `(mtime, len)`, return cached or reparse + sanitize + insert.
- `Cache::invalidate(path: &Path)` — remove entry.
- `Cache::sweep() -> usize` — remove entries whose path no longer exists; return count.
- `scanner::cold_scan(root, cache)` — walk `projects/*/specs/**`, populate cache.

## Implementation Notes

- Ammonia allowlist: tags `{p,h1..h6,ul,ol,li,strong,em,code,pre,blockquote,a,table,thead,tbody,tr,th,td,hr,br,img,span,div}`; attrs `{href,src,alt,title,class,id,colspan,rowspan}`; `url_schemes({"http","https","mailto"})`; `url_relative(UrlRelative::Deny)`.
- File-size cap is shared constant in `limits.rs` (re-used by API in task 4).
- DashMap chosen per ADR-003 — no `RwLock`.
- Mermaid block detection during parse: walk `pulldown-cmark` events, count CodeBlock(lang="mermaid") byte length; reject > 16 KiB with `CoreError::TooLarge`.
- All errors via `thiserror`-derived `CoreError` (`general:languages/rust/error-handling.md`). Don't leak details — API task wraps these.
