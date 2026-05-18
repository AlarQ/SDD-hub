use serde::Deserialize;
use serde::de::Deserializer;
use std::fmt;

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum TaskStatus {
    Blocked,
    Todo,
    InProgress,
    Implemented,
    Review,
    Done,
}

impl fmt::Display for TaskStatus {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Blocked => write!(f, "blocked"),
            Self::Todo => write!(f, "todo"),
            Self::InProgress => write!(f, "in-progress"),
            Self::Implemented => write!(f, "implemented"),
            Self::Review => write!(f, "review"),
            Self::Done => write!(f, "done"),
        }
    }
}

/// How a task gets completed: autonomously, or with a human in the loop.
/// Absent in frontmatter → `Afk` (backward compatible with pre-existing tasks).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize, Default)]
#[serde(rename_all = "lowercase")]
pub enum Interaction {
    Hitl,
    #[default]
    Afk,
}

impl fmt::Display for Interaction {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Hitl => write!(f, "hitl"),
            Self::Afk => write!(f, "afk"),
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
#[allow(dead_code)]
pub struct Task {
    pub id: String,
    pub name: String,
    pub status: TaskStatus,
    #[serde(default)]
    pub blocked_by: Vec<String>,
    #[serde(default, deserialize_with = "deserialize_flexible_u32")]
    pub max_files: u32,
    #[serde(default, deserialize_with = "deserialize_flexible_vec")]
    pub estimated_files: Vec<String>,
    #[serde(default)]
    pub test_cases: Vec<String>,
    #[serde(default)]
    pub ground_rules: Vec<String>,
    #[serde(default)]
    pub interaction: Interaction,
}

/// Deserialize a u32 from any YAML scalar (number or quoted string).
fn deserialize_flexible_u32<'de, D>(deserializer: D) -> Result<u32, D::Error>
where
    D: Deserializer<'de>,
{
    let value = serde_yml::Value::deserialize(deserializer)?;
    match value {
        serde_yml::Value::Number(n) => n
            .as_u64()
            .map(|v| v as u32)
            .ok_or_else(|| serde::de::Error::custom("expected unsigned integer")),
        serde_yml::Value::String(s) => s.parse().map_err(serde::de::Error::custom),
        serde_yml::Value::Null => Ok(0),
        _ => Ok(0),
    }
}

/// Deserialize a list of strings from any YAML sequence; non-sequence values yield an empty vec.
fn deserialize_flexible_vec<'de, D>(deserializer: D) -> Result<Vec<String>, D::Error>
where
    D: Deserializer<'de>,
{
    let value = serde_yml::Value::deserialize(deserializer)?;
    match value {
        serde_yml::Value::Sequence(seq) => seq
            .into_iter()
            .map(|v| match v {
                serde_yml::Value::String(s) => Ok(s),
                other => Ok(serde_yml::to_string(&other)
                    .unwrap_or_default()
                    .trim()
                    .to_string()),
            })
            .collect(),
        serde_yml::Value::Null => Ok(Vec::new()),
        _ => Ok(Vec::new()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn deserialize_status_kebab_case() {
        let yaml = r#"
id: "001"
name: "test task"
status: in-progress
blocked_by: []
max_files: 5
estimated_files: []
test_cases: []
ground_rules: []
"#;
        let task: Task = serde_yml::from_str(yaml).unwrap();
        assert_eq!(task.status, TaskStatus::InProgress);
        assert_eq!(task.id, "001");
    }

    #[test]
    fn deserialize_status_done() {
        let yaml = r#"
id: "002"
name: "done task"
status: done
"#;
        let task: Task = serde_yml::from_str(yaml).unwrap();
        assert_eq!(task.status, TaskStatus::Done);
    }
}
