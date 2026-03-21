use crate::app::App;
use crate::ui::styles;
use ratatui::layout::Rect;
use ratatui::style::Style;
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Borders, List, ListItem};
use ratatui::Frame;

pub fn render(frame: &mut Frame, app: &App, area: Rect, active: bool) {
    let block = Block::default()
        .title(" Specs & Tasks ")
        .borders(Borders::ALL)
        .border_style(styles::panel_border(active));

    if app.specs.is_empty() {
        let items: Vec<ListItem> = vec![ListItem::new("  No specs found. Ensure specs/ directory exists.")];
        let list = List::new(items).block(block);
        frame.render_widget(list, area);
        return;
    }

    let mut items: Vec<ListItem> = Vec::new();

    for (i, spec) in app.specs.iter().enumerate() {
        let marker = if i == app.selected_spec { ">" } else { " " };
        let spec_style = if i == app.selected_spec {
            styles::selected_style()
        } else {
            styles::header_style()
        };

        let pct = spec.progress_percent();
        items.push(ListItem::new(Line::from(vec![
            Span::styled(
                format!("{marker} {name} ({pct}%)", name = spec.name),
                spec_style,
            ),
        ])));

        for task in &spec.tasks {
            let status_color = task.status.color();
            items.push(ListItem::new(Line::from(vec![
                Span::raw("    "),
                Span::styled(&task.id, Style::default().fg(status_color)),
                Span::raw(" "),
                Span::raw(&task.name),
                Span::raw(" ["),
                Span::styled(task.status.to_string(), Style::default().fg(status_color)),
                Span::raw("]"),
            ])));
        }
    }

    let list = List::new(items).block(block);
    frame.render_widget(list, area);
}
