use crate::model::Report;
use anyhow::{Context, Result};

pub fn parse_report(content: &str, path: &str) -> Result<Report> {
    serde_yml::from_str(content).with_context(|| format!("invalid report YAML in {path}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_valid_report() {
        let yaml = r#"
gate: lint
task_id: "001"
status: pass
findings: []
"#;
        let report = parse_report(yaml, "test.yaml").unwrap();
        assert_eq!(report.gate, "lint");
        assert_eq!(report.task_id, "001");
        assert!(report.findings.is_empty());
    }

    #[test]
    fn parses_report_with_findings() {
        let yaml = r#"
gate: security
task_id: "002"
status: findings
findings:
  - id: F001
    severity: warning
    title: "Missing validation"
    description: "Input not validated"
"#;
        let report = parse_report(yaml, "test.yaml").unwrap();
        assert_eq!(report.findings.len(), 1);
        assert_eq!(report.findings[0].severity, "warning");
    }

    #[test]
    fn parses_minimal_report() {
        let yaml = "{}";
        let report = parse_report(yaml, "test.yaml").unwrap();
        assert!(report.gate.is_empty());
        assert!(report.findings.is_empty());
    }

    #[test]
    fn rejects_invalid_yaml() {
        let yaml = "{{invalid: yaml: [";
        assert!(parse_report(yaml, "test.yaml").is_err());
    }
}
