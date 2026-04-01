# Security Rules

## Input Validation
1. **Validate and sanitize all user input** — never trust data from external sources (HTTP requests, file uploads, CLI arguments, environment variables from untrusted contexts)
2. **Check for null/nil/None values** at system boundaries — validate data types, ranges, and constraints before processing
3. **Prevent injection attacks** — use parameterized queries for SQL, escape output for HTML/JS (XSS), validate file paths against traversal (`../`)

## Secrets and Credentials
4. **Never log passwords, tokens, or API keys** — scrub sensitive fields from log output and error messages
5. **Use environment variables for secrets** — never hardcode credentials, connection strings, or API keys in source code
6. **Never expose internal error details to users** — return safe error messages; log full details server-side only

## Access Control
7. **Follow the principle of least privilege** — grant minimum permissions required; default to deny
8. **Validate file paths and permissions** — prevent path traversal attacks; reject paths containing `..` or absolute paths when relative are expected

## Dependencies
9. **Pin dependency versions** — use lock files; audit dependencies for known vulnerabilities (CVE databases, `npm audit`, `cargo audit`, etc.)
10. **Minimize the dependency surface** — each dependency is an attack vector; document why each is needed
