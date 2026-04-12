use crate::model::Task;
use crate::parse::frontmatter::extract_frontmatter;
use anyhow::{Context, Result};

pub fn parse_task(content: &str, path: &str) -> Result<Task> {
    let yaml = extract_frontmatter(content).with_context(|| format!("no frontmatter in {path}"))?;
    serde_yml::from_str(&yaml).with_context(|| format!("invalid task YAML in {path}"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::TaskStatus;

    #[test]
    fn parses_full_task() {
        let content = r#"---
id: "003"
name: "add auth middleware"
status: blocked
blocked_by:
  - "001"
  - "002"
max_files: 8
estimated_files:
  - src/middleware/auth.rs
test_cases:
  - "should reject unauthenticated requests"
ground_rules:
  - general:security/general.md
  - project:languages/rust.md
---

# Implementation Notes
Details here.
"#;
        let task = parse_task(content, "test.md").unwrap();
        assert_eq!(task.id, "003");
        assert_eq!(task.status, TaskStatus::Blocked);
        assert_eq!(task.blocked_by, vec!["001", "002"]);
        assert_eq!(task.max_files, 8);
    }
}
