use serde::Deserialize;

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum ReportStatus {
    Pass,
    Findings,
    Error,
}

/// Accept any YAML shape (string, object, number) without failing deserialization.
fn deserialize_flexible_string<'de, D>(deserializer: D) -> Result<String, D::Error>
where
    D: serde::Deserializer<'de>,
{
    let value = serde_yml::Value::deserialize(deserializer)?;
    match value {
        serde_yml::Value::String(s) => Ok(s),
        serde_yml::Value::Null => Ok(String::new()),
        other => Ok(serde_yml::to_string(&other)
            .unwrap_or_default()
            .trim()
            .to_string()),
    }
}

#[derive(Debug, Clone, Deserialize)]
#[allow(dead_code)]
pub struct Finding {
    #[serde(default)]
    pub id: String,
    #[serde(default)]
    pub severity: String,
    #[serde(default)]
    pub category: String,
    #[serde(default)]
    pub title: String,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub file: String,
    #[serde(default, deserialize_with = "deserialize_flexible_string")]
    pub lines: String,
    #[serde(default)]
    pub code_snippet: String,
    #[serde(default, deserialize_with = "deserialize_flexible_string")]
    pub fix_proposal: String,
    #[serde(default)]
    pub review_status: String,
    #[serde(default)]
    pub source: String,
}

#[derive(Debug, Clone, Deserialize)]
#[allow(dead_code)]
pub struct Report {
    #[serde(default)]
    pub gate: String,
    #[serde(default)]
    pub task_id: String,
    #[serde(default)]
    pub status: Option<ReportStatus>,
    #[serde(default)]
    pub findings: Vec<Finding>,
}
