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
    // [spec-review-1] widened to cover categories present in live
    // .monitor.jsonl and emitted by monitor.sh. Any category not named here
    // deserializes to `Unknown` (final `#[serde(other)]` arm) rather than
    // triggering a ParseWarning::MalformedLine skip — keeps the event
    // renderable instead of silently dropped.
    ConfigApproved,
    TierApproved,
    TierBreach,
    TddRed,
    TddGreen,
    PrOpenedDraft,
    GateRepoSwitch,
    RepoMissing,
    SpecLastTaskDone,
    #[serde(other)]
    Unknown,
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

#[cfg(test)]
mod tests {
    use super::*;

    // [spec-review-1] a known-widened category deserializes to its typed
    // variant, not an error.
    #[test]
    fn config_approved_deserializes_to_typed_variant() {
        let line = r#"{"ts":"2026-05-18T00:00:00.000Z","category":"config_approved","feature":"x","data":{}}"#;
        let ev: MonitorEvent = serde_json::from_str(line).unwrap();
        assert_eq!(ev.category, EventCategory::ConfigApproved);
    }

    #[test]
    fn tier_approved_deserializes_to_typed_variant() {
        let line = r#"{"ts":"2026-05-18T00:00:00.000Z","category":"tier_approved","feature":"x","data":{}}"#;
        let ev: MonitorEvent = serde_json::from_str(line).unwrap();
        assert_eq!(ev.category, EventCategory::TierApproved);
    }

    // [spec-review-1] an unrecognised category falls through to `Unknown`
    // (renderable) rather than failing deserialization.
    #[test]
    fn unknown_category_deserializes_to_unknown_variant() {
        let line = r#"{"ts":"2026-05-18T00:00:00.000Z","category":"something_brand_new","feature":"x","data":{}}"#;
        let ev: MonitorEvent = serde_json::from_str(line).unwrap();
        assert_eq!(ev.category, EventCategory::Unknown);
    }
}
