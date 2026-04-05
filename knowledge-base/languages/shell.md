# Shell (Bash) Code Quality Standards

validation_tools:
  - bash -n <file>
  - shellcheck <file>

## Rules

- **Module size limit is 150 lines** — shell scripts have different composition patterns than application modules; the general 100-line guideline is relaxed to 150 lines for `.sh` files
- **python3 is acceptable as a test dependency** — while the project targets minimal runtime dependencies (`yq`), `python3` may be used in test suites for validation tasks like JSON parsing
