use crate::app::App;
use crate::ui::styles;
use ratatui::Frame;
use ratatui::layout::Rect;
use ratatui::style::Style;
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Borders, Paragraph, Wrap};
use std::collections::HashMap;

pub fn render(frame: &mut Frame, app: &App, area: Rect, active: bool) {
    let block = Block::default()
        .title(" Dependency Graph ")
        .borders(Borders::ALL)
        .border_style(styles::panel_border(active));

    let spec = match app.current_spec() {
        Some(s) => s,
        None => {
            let p = Paragraph::new("  Select a spec").block(block);
            frame.render_widget(p, area);
            return;
        }
    };

    // Build reverse dep map: task_id -> list of task_ids it unblocks
    let mut unblocks: HashMap<&str, Vec<&str>> = HashMap::new();
    for task in &spec.tasks {
        for dep in &task.blocked_by {
            unblocks.entry(dep.as_str()).or_default().push(&task.id);
        }
    }

    let mut lines: Vec<Line> = Vec::new();

    for task in &spec.tasks {
        let status_color = task.status.color();
        let mut spans = vec![
            Span::styled(&task.id, Style::default().fg(status_color)),
            Span::raw(format!(" ({})", task.status)),
        ];

        if let Some(unblocked) = unblocks.get(task.id.as_str()) {
            spans.push(Span::raw(" -> unblocks "));
            spans.push(Span::raw(unblocked.join(", ")));
        }

        if !task.blocked_by.is_empty() {
            spans.push(Span::raw(format!(
                " [blocked by: {}]",
                task.blocked_by.join(", ")
            )));
        }

        lines.push(Line::from(spans));
    }

    if lines.is_empty() {
        lines.push(Line::from("  No tasks"));
    }

    let paragraph = Paragraph::new(lines)
        .block(block)
        .wrap(Wrap { trim: true })
        .scroll((app.scroll_offset.min(u16::MAX as usize) as u16, 0));

    frame.render_widget(paragraph, area);
}
