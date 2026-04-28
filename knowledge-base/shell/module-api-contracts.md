# Shell Module API Contracts

## Rules

When a script sources a leaf module (e.g., `config-paths.sh`) that defines public functions:

1. **Never redefine public symbols.** If a consumer needs an extended version of a leaf function, give it a private name (prefix with `_<module>_`). Leave the canonical function untouched.
2. **Private helpers use underscore prefix.** Functions not in the declared public sourcing API must be prefixed with `_` to signal they are not part of the public contract.
3. **Document env-var contracts.** At hook/script boundaries that eval or export WF_* variables, add a comment listing which variables are consumed downstream.
