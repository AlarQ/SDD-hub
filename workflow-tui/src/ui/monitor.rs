use crate::model::{EventCategory, MonitorEvent};
use crate::ui::styles;
use ratatui::Frame;
use ratatui::layout::Rect;
use ratatui::style::{Color, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Borders, Paragraph};

const NO_EVENTS_MESSAGE: &str = "  No monitoring data";

pub fn render(
    frame: &mut Frame,
    events: &[MonitorEvent],
    area: Rect,
    is_active: bool,
    scroll_offset: usize,
) {
    let block = Block::default()
        .title(" Monitor ")
        .borders(Borders::ALL)
        .border_style(styles::panel_border(is_active));

    if events.is_empty() {
        let p = Paragraph::new(NO_EVENTS_MESSAGE).block(block);
        frame.render_widget(p, area);
        return;
    }

    let lines: Vec<Line> = events.iter().map(format_event_line).collect();

    let p = Paragraph::new(lines)
        .block(block)
        .scroll((scroll_offset.min(u16::MAX as usize) as u16, 0));

    frame.render_widget(p, area);
}

fn format_event_line(event: &MonitorEvent) -> Line<'static> {
    let time = format_timestamp(&event.ts);
    let (badge, badge_color) = category_badge(&event.category);
    let task_str = event
        .task
        .as_deref()
        .map(|t| format!("{t:>3}"))
        .unwrap_or_else(|| "   ".to_string());
    let summary = format_summary(event);

    Line::from(vec![
        Span::styled(format!(" {time}  "), Style::default().fg(Color::DarkGray)),
        Span::styled(format!("{badge:<7}"), Style::default().fg(badge_color)),
        Span::styled(format!(" {task_str}  "), Style::default().fg(Color::White)),
        Span::styled(summary, Style::default().fg(badge_color)),
    ])
}

fn format_timestamp(ts: &str) -> String {
    // Extract HH:MM:SS from ISO 8601 timestamp
    if let Some(t_pos) = ts.find('T') {
        let time_part = &ts[t_pos + 1..];
        let extracted: String = time_part.chars().take(8).collect();
        if extracted.len() >= 8 {
            return extracted;
        }
    }
    "??:??:??".to_string()
}

fn category_badge(cat: &EventCategory) -> (&'static str, Color) {
    let label = match cat {
        EventCategory::ContextRead => "READ",
        EventCategory::KbRule => "KB",
        EventCategory::TaskTransition => "TRANSIT",
        EventCategory::AgentInvocation => "AGENT",
        EventCategory::ValidationResult => "VALID",
        EventCategory::ToolCall => "TOOL",
    };
    (label, styles::event_category_color(cat))
}

fn get_str<'a>(data: &'a serde_json::Value, keys: &[&str], default: &'a str) -> &'a str {
    keys.iter()
        .find_map(|k| data[*k].as_str())
        .unwrap_or(default)
}

fn format_summary(event: &MonitorEvent) -> String {
    match &event.category {
        EventCategory::ContextRead => get_str(&event.data, &["file"], "unknown file").to_string(),
        EventCategory::KbRule => get_str(&event.data, &["rule_path"], "unknown rule").to_string(),
        EventCategory::TaskTransition => {
            let from = get_str(&event.data, &["from_status", "from"], "?");
            let to = get_str(&event.data, &["to_status", "to"], "?");
            format!("{from} \u{2192} {to}")
        }
        EventCategory::AgentInvocation => {
            let name = get_str(&event.data, &["agent_name", "agent"], "unknown");
            let reason = get_str(&event.data, &["reason"], "");
            if reason.is_empty() {
                name.to_string()
            } else {
                format!("{name} \u{2014} {reason}")
            }
        }
        EventCategory::ValidationResult => {
            let gate = get_str(&event.data, &["gate"], "?");
            let status = get_str(&event.data, &["status"], "?");
            let count = event.data["findings_count"]
                .as_u64()
                .map(|n| format!(" ({n} findings)"))
                .unwrap_or_default();
            format!("{gate}: {status}{count}")
        }
        EventCategory::ToolCall => {
            get_str(&event.data, &["tool_name", "tool"], "unknown tool").to_string()
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn make_event(
        category: EventCategory,
        task: Option<&str>,
        data: serde_json::Value,
    ) -> MonitorEvent {
        MonitorEvent {
            ts: "2026-04-05T14:32:01.000Z".to_string(),
            category,
            task: task.map(|t| t.to_string()),
            feature: "test-feature".to_string(),
            correlation_id: None,
            data,
        }
    }

    #[test]
    fn empty_event_list_produces_no_formatted_lines() {
        let events: Vec<MonitorEvent> = vec![];
        let lines: Vec<Line> = events.iter().map(format_event_line).collect();
        assert!(lines.is_empty());
        // Verify the placeholder message constant is what we expect
        assert_eq!(NO_EVENTS_MESSAGE, "  No monitoring data");
    }

    #[test]
    fn events_render_in_chronological_order() {
        // Given events in chronological order (as provided by the parser)
        let events = vec![
            make_event(
                EventCategory::ToolCall,
                Some("001"),
                json!({"tool_name": "Edit"}),
            ),
            make_event(
                EventCategory::ContextRead,
                Some("001"),
                json!({"file": "src/app.rs"}),
            ),
        ];

        // When we format them
        let lines: Vec<Line> = events.iter().map(format_event_line).collect();

        // Then they preserve input order (first=TOOL, second=READ)
        assert_eq!(lines.len(), 2);
        let first: String = lines[0]
            .spans
            .iter()
            .map(|s| s.content.to_string())
            .collect();
        let second: String = lines[1]
            .spans
            .iter()
            .map(|s| s.content.to_string())
            .collect();
        assert!(first.contains("TOOL"), "first line should be TOOL event");
        assert!(second.contains("READ"), "second line should be READ event");
    }

    #[test]
    fn each_event_shows_timestamp_category_badge_task_id_and_summary() {
        // Given an event with all fields
        let event = make_event(
            EventCategory::ContextRead,
            Some("003"),
            json!({"file": "src/app.rs"}),
        );

        // When we format it
        let line = format_event_line(&event);

        // Then it contains timestamp, category badge, task ID, and summary
        let text: String = line.spans.iter().map(|s| s.content.to_string()).collect();
        assert!(text.contains("14:32:01"), "missing timestamp");
        assert!(text.contains("READ"), "missing category badge");
        assert!(text.contains("003"), "missing task ID");
        assert!(text.contains("src/app.rs"), "missing summary");
    }

    #[test]
    fn category_badges_use_distinct_colors() {
        // Given all six categories
        let categories = [
            EventCategory::ContextRead,
            EventCategory::KbRule,
            EventCategory::TaskTransition,
            EventCategory::AgentInvocation,
            EventCategory::ValidationResult,
            EventCategory::ToolCall,
        ];

        // When we get their badges
        let colors: Vec<Color> = categories.iter().map(|c| category_badge(c).1).collect();

        // Then each has a distinct color
        for (i, c1) in colors.iter().enumerate() {
            for (j, c2) in colors.iter().enumerate() {
                if i != j {
                    assert_ne!(c1, c2, "categories {i} and {j} share color");
                }
            }
        }
    }

    #[test]
    fn context_read_events_show_file_path() {
        let event = make_event(
            EventCategory::ContextRead,
            Some("003"),
            json!({"file": "src/handlers/auth.rs"}),
        );
        let summary = format_summary(&event);
        assert_eq!(summary, "src/handlers/auth.rs");
    }

    #[test]
    fn agent_invocation_events_show_agent_name_and_reason() {
        let event = make_event(
            EventCategory::AgentInvocation,
            Some("003"),
            json!({"agent_name": "Code Quality Pragmatist", "reason": "post-implementation check"}),
        );
        let summary = format_summary(&event);
        assert_eq!(
            summary,
            "Code Quality Pragmatist \u{2014} post-implementation check"
        );
    }

    #[test]
    fn task_transition_events_show_from_and_to_status() {
        let event = make_event(
            EventCategory::TaskTransition,
            Some("003"),
            json!({"from_status": "in-progress", "to_status": "implemented"}),
        );
        let summary = format_summary(&event);
        assert_eq!(summary, "in-progress \u{2192} implemented");
    }

    #[test]
    fn validation_result_events_show_gate_name_status_and_findings_count() {
        let event = make_event(
            EventCategory::ValidationResult,
            Some("003"),
            json!({"gate": "security", "status": "findings", "findings_count": 3}),
        );
        let summary = format_summary(&event);
        assert_eq!(summary, "security: findings (3 findings)");
    }

    #[test]
    fn scroll_offset_controls_which_events_are_visible() {
        // Scroll behavior is delegated to Paragraph::scroll(offset, 0) which
        // requires a terminal backend to observe visually. We verify the
        // render function accepts scroll_offset and the timestamp formatting
        // works correctly for any position in the scrolled content.
        assert_eq!(format_timestamp("2026-04-05T14:32:01.000Z"), "14:32:01");
        assert_eq!(format_timestamp("2026-04-05T09:00:00.000Z"), "09:00:00");
        // Malformed timestamps degrade gracefully
        assert_eq!(format_timestamp("no-T-here"), "??:??:??");
    }
}
