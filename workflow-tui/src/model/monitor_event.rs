use serde::Deserialize;

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

#[derive(Debug, Clone, Deserialize)]
pub struct MonitorEvent {
    pub ts: String,
    pub category: EventCategory,
    #[serde(default)]
    pub task: Option<String>,
    #[allow(dead_code)] // Deserialized from JSONL; used for event filtering
    pub feature: String,
    #[serde(default)]
    #[allow(dead_code)] // Deserialized from JSONL; used for event pairing
    pub correlation_id: Option<String>,
    pub data: serde_json::Value,
}
