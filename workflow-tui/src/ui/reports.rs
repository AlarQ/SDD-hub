use crate::app::App;
use crate::ui::styles;
use ratatui::layout::{Constraint, Rect};
use ratatui::style::Style;
use ratatui::widgets::{Block, Borders, Cell, Row, Table};
use ratatui::Frame;

pub fn render(frame: &mut Frame, app: &App, area: Rect, active: bool) {
    let block = Block::default()
        .title(" Validation Reports ")
        .borders(Borders::ALL)
        .border_style(styles::panel_border(active));

    let spec = match app.current_spec() {
        Some(s) => s,
        None => {
            let table = Table::new(Vec::<Row>::new(), [Constraint::Min(1)])
                .block(block);
            frame.render_widget(table, area);
            return;
        }
    };

    let header = Row::new(vec![
        Cell::from("Severity"),
        Cell::from("Gate"),
        Cell::from("Title"),
        Cell::from("Source"),
        Cell::from("Review"),
    ])
    .style(styles::header_style());

    let mut rows: Vec<Row> = Vec::new();
    for report in &spec.reports {
        for finding in &report.findings {
            let sev_color = styles::severity_color(&finding.severity);
            rows.push(Row::new(vec![
                Cell::from(finding.severity.as_str())
                    .style(Style::default().fg(sev_color)),
                Cell::from(report.gate.as_str()),
                Cell::from(finding.title.as_str()),
                Cell::from(finding.source.as_str()),
                Cell::from(finding.review_status.as_str()),
            ]));
        }
    }

    if rows.is_empty() {
        rows.push(Row::new(vec![
            Cell::from(""),
            Cell::from(""),
            Cell::from("No findings"),
            Cell::from(""),
            Cell::from(""),
        ]));
    }

    let widths = [
        Constraint::Length(10),
        Constraint::Length(14),
        Constraint::Percentage(40),
        Constraint::Length(8),
        Constraint::Length(10),
    ];

    let table = Table::new(rows, widths)
        .header(header)
        .block(block);

    frame.render_widget(table, area);
}
