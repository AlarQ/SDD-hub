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

pub fn severity_color(severity: &str) -> Color {
    match severity.to_lowercase().as_str() {
        "critical" | "error" => Color::Red,
        "warning" | "warn" => Color::Yellow,
        "info" | "note" => Color::Cyan,
        _ => Color::White,
    }
}
