use ratatui::style::{Color, Modifier, Style};

pub fn panel_border(active: bool) -> Style {
    if active {
        Style::default()
            .fg(Color::Cyan)
            .add_modifier(Modifier::BOLD)
    } else {
        Style::default().fg(Color::DarkGray)
    }
}

pub fn header_style() -> Style {
    Style::default()
        .fg(Color::White)
        .add_modifier(Modifier::BOLD)
}

pub fn selected_style() -> Style {
    Style::default()
        .bg(Color::DarkGray)
        .add_modifier(Modifier::BOLD)
}

#[allow(dead_code)] // Used by monitor panel rendering in task 006
pub fn event_category_color(cat: &crate::model::EventCategory) -> Color {
    match cat {
        crate::model::EventCategory::ContextRead => Color::Cyan,
        crate::model::EventCategory::KbRule => Color::Blue,
        crate::model::EventCategory::TaskTransition => Color::Yellow,
        crate::model::EventCategory::AgentInvocation => Color::Magenta,
        crate::model::EventCategory::ValidationResult => Color::Green,
        crate::model::EventCategory::ToolCall => Color::Gray,
    }
}

pub fn severity_color(severity: &str) -> Color {
    match severity.to_lowercase().as_str() {
        "critical" | "error" => Color::Red,
        "warning" | "warn" => Color::Yellow,
        "info" | "note" => Color::Cyan,
        _ => Color::White,
    }
}
