use crate::model::MonitorEvent;
use crate::parse::ParseWarning;
use crate::parse::limits::MAX_EVENTS;

pub fn parse_monitor_log(content: &str, source: &str) -> (Vec<MonitorEvent>, Vec<ParseWarning>) {
    let mut events = Vec::new();
    let mut warnings = Vec::new();

    for (i, line) in content.lines().enumerate() {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        match serde_json::from_str::<MonitorEvent>(line) {
            Ok(event) => {
                events.push(event);
                if events.len() >= MAX_EVENTS {
                    warnings.push(ParseWarning::Truncated {
                        source: source.to_string(),
                        max: MAX_EVENTS,
                    });
                    break;
                }
            }
            Err(e) => warnings.push(ParseWarning::MalformedLine {
                source: source.to_string(),
                line: i + 1,
                cause: e.to_string(),
            }),
        }
    }

    (events, warnings)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::EventCategory;

    fn valid_event(category: &str) -> String {
        format!(
            r#"{{"ts":"2026-04-05T14:32:01.000Z","category":"{category}","feature":"my-feature","data":{{}}}}"#
        )
    }

    #[test]
    fn parse_valid_jsonl_line_into_monitor_event() {
        // Given a valid JSONL line with all fields
        let line = r#"{"ts":"2026-04-05T14:32:01.000Z","category":"context_read","task":"003","feature":"auth-system","correlation_id":"impl-003-1712345678","data":{"file":"src/app.rs"}}"#;

        // When we parse it
        let (events, warnings) = parse_monitor_log(line, "test");

        // Then we get one event with correct fields
        assert_eq!(events.len(), 1);
        assert!(warnings.is_empty());
        let event = &events[0];
        assert_eq!(event.ts, "2026-04-05T14:32:01.000Z");
        assert_eq!(event.category, EventCategory::ContextRead);
        assert_eq!(event.task.as_deref(), Some("003"));
        assert_eq!(event.feature, "auth-system");
        assert_eq!(event.correlation_id.as_deref(), Some("impl-003-1712345678"));
        assert_eq!(event.data["file"], "src/app.rs");
    }

    #[test]
    fn parse_known_event_categories_correctly() {
        // Given JSONL lines for each known category (original six +
        // [spec-review-1] widened set)
        let categories = [
            ("context_read", EventCategory::ContextRead),
            ("kb_rule", EventCategory::KbRule),
            ("task_transition", EventCategory::TaskTransition),
            ("agent_invocation", EventCategory::AgentInvocation),
            ("validation_result", EventCategory::ValidationResult),
            ("tool_call", EventCategory::ToolCall),
            ("config_approved", EventCategory::ConfigApproved),
            ("tier_approved", EventCategory::TierApproved),
        ];

        for (snake, expected) in &categories {
            // When we parse a line with this category
            let (events, warnings) = parse_monitor_log(&valid_event(snake), "test");

            // Then the category deserializes correctly
            assert!(warnings.is_empty(), "unexpected warning for {snake}");
            assert_eq!(events.len(), 1);
            assert_eq!(&events[0].category, expected);
        }
    }

    // [spec-review-1] an unrecognised category must NOT produce a
    // ParseWarning::MalformedLine skip — it deserializes to
    // EventCategory::Unknown and the event is retained.
    #[test]
    fn unknown_category_is_retained_not_skipped() {
        let (events, warnings) = parse_monitor_log(&valid_event("brand_new_thing"), "test");
        assert!(warnings.is_empty());
        assert_eq!(events.len(), 1);
        assert_eq!(events[0].category, EventCategory::Unknown);
    }

    #[test]
    fn skip_empty_lines_without_warning() {
        // Given content with empty lines interspersed
        let content = format!(
            "\n\n{}\n\n{}\n\n",
            valid_event("tool_call"),
            valid_event("kb_rule")
        );

        // When we parse it
        let (events, warnings) = parse_monitor_log(&content, "test");

        // Then empty lines are skipped and no warnings are produced
        assert_eq!(events.len(), 2);
        assert!(warnings.is_empty());
    }

    #[test]
    fn skip_malformed_lines_with_warning_including_line_number() {
        // Given content with a valid line and a malformed line
        let content = format!(
            "{}\nnot-json\n{}",
            valid_event("tool_call"),
            valid_event("kb_rule")
        );

        // When we parse it
        let (events, warnings) = parse_monitor_log(&content, "monitor.jsonl");

        // Then valid lines parse and malformed line produces a warning with line number
        assert_eq!(events.len(), 2);
        assert_eq!(warnings.len(), 1);
        assert!(warnings[0].to_string().starts_with("monitor.jsonl:2:"));
    }

    #[test]
    fn parse_event_with_missing_optional_fields() {
        // Given a JSONL line without task or correlation_id
        let line = r#"{"ts":"2026-04-05T14:32:01.000Z","category":"kb_rule","feature":"my-feature","data":{"rule":"security.md"}}"#;

        // When we parse it
        let (events, warnings) = parse_monitor_log(line, "test");

        // Then optional fields default to None
        assert_eq!(events.len(), 1);
        assert!(warnings.is_empty());
        assert!(events[0].task.is_none());
        assert!(events[0].correlation_id.is_none());
    }

    #[test]
    fn parse_event_with_arbitrary_json_in_data_field() {
        // Given a JSONL line with nested, complex data
        let line = r#"{"ts":"2026-04-05T14:32:01.000Z","category":"validation_result","feature":"my-feature","data":{"gate":"security","status":"findings","findings_count":3,"details":{"critical":1,"high":2}}}"#;

        // When we parse it
        let (events, warnings) = parse_monitor_log(line, "test");

        // Then data is preserved as arbitrary JSON
        assert_eq!(events.len(), 1);
        assert!(warnings.is_empty());
        assert_eq!(events[0].data["findings_count"], 3);
        assert_eq!(events[0].data["details"]["critical"], 1);
    }
}
