---
id: "002"
name: "fixture task"
status: in-progress
blocked_by:
  - "001"
max_files: 7
estimated_files:
  - src/lib.rs
test_cases:
  - "does the thing"
interaction: hitl
ground_rules:
  - general:languages/rust/_index.md
---

# Notes

Shared parser fixture — consumed by workflow-web tasks 003/005/006.
