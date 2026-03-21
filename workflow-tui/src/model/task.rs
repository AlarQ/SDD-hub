use ratatui::style::Color;
use serde::de::{self, Deserializer};
use serde::Deserialize;
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

impl TaskStatus {
    pub fn color(&self) -> Color {
        match self {
            Self::Blocked => Color::Red,
            Self::Todo => Color::Gray,
            Self::InProgress => Color::Yellow,
            Self::Implemented => Color::Cyan,
            Self::Review => Color::Magenta,
            Self::Done => Color::Green,
        }
    }
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
}

/// Deserialize a value that can be either a number or a list of strings.
/// A bare number becomes an empty vec; a list is kept as-is.
fn deserialize_flexible_vec<'de, D>(deserializer: D) -> Result<Vec<String>, D::Error>
where
    D: Deserializer<'de>,
{
    #[derive(Deserialize)]
    #[serde(untagged)]
    enum FlexVec {
        #[allow(dead_code)]
        Num(u32),
        List(Vec<String>),
    }

    match FlexVec::deserialize(deserializer) {
        Ok(FlexVec::List(v)) => Ok(v),
        Ok(FlexVec::Num(_)) => Ok(Vec::new()),
        Err(_) => Ok(Vec::new()),
    }
}

/// Deserialize a value that can be either a number or a string representation of a number.
fn deserialize_flexible_u32<'de, D>(deserializer: D) -> Result<u32, D::Error>
where
    D: Deserializer<'de>,
{
    #[derive(Deserialize)]
    #[serde(untagged)]
    enum FlexNum {
        Num(u32),
        Str(String),
    }

    match FlexNum::deserialize(deserializer) {
        Ok(FlexNum::Num(n)) => Ok(n),
        Ok(FlexNum::Str(s)) => s.parse().map_err(de::Error::custom),
        Err(_) => Ok(0),
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

    #[test]
    fn status_colors_are_distinct() {
        let statuses = [
            TaskStatus::Blocked,
            TaskStatus::Todo,
            TaskStatus::InProgress,
            TaskStatus::Done,
        ];
        for (i, a) in statuses.iter().enumerate() {
            for b in statuses.iter().skip(i + 1) {
                assert_ne!(a.color(), b.color());
            }
        }
    }
}
