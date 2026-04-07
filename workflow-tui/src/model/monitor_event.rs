use serde::Deserialize;

#[allow(dead_code)] // Used by TUI rendering in later tasks
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EventCategory {
    ContextRead,
    KbRule,
    TaskTransition,
    AgentInvocation,
    ValidationResult,
    ToolCall,
}

#[allow(dead_code)] // Used by scanner and TUI in later tasks
#[derive(Debug, Clone, Deserialize)]
pub struct MonitorEvent {
    pub ts: String,
    pub category: EventCategory,
    #[serde(default)]
    pub task: Option<String>,
    pub feature: String,
    #[serde(default)]
    pub correlation_id: Option<String>,
    pub data: serde_json::Value,
}
