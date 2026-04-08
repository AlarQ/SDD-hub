use crate::app::App;
use crate::model::{Spec, TaskStatus};
use crate::ui::styles;
use ratatui::Frame;
use ratatui::layout::{Constraint, Direction, Layout, Rect};
use ratatui::style::{Color, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Borders, Gauge, Paragraph};

pub fn render(frame: &mut Frame, app: &App, area: Rect, active: bool) {
    let block = Block::default()
        .title(" Progress ")
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

    let inner = block.inner(area);
    frame.render_widget(block, area);

    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Length(3), Constraint::Min(1)])
        .split(inner);

    render_gauge(frame, spec, chunks[0]);
    render_details(frame, spec, &app.warnings, chunks[1]);
}

fn render_gauge(frame: &mut Frame, spec: &Spec, area: Rect) {
    let pct = spec.progress_percent();
    let gauge = Gauge::default()
        .gauge_style(Style::default().fg(Color::Green).bg(Color::DarkGray))
        .percent(pct)
        .label(format!("{pct}% complete"));
    frame.render_widget(gauge, area);
}

fn render_details(frame: &mut Frame, spec: &Spec, warnings: &[String], area: Rect) {
    let total = spec.tasks.len();
    let done = spec.count_by_status(TaskStatus::Done);
    let todo = spec.count_by_status(TaskStatus::Todo);
    let in_progress = spec.count_by_status(TaskStatus::InProgress);
    let implemented = spec.count_by_status(TaskStatus::Implemented);
    let review = spec.count_by_status(TaskStatus::Review);
    let blocked = spec.count_by_status(TaskStatus::Blocked);

    let mut lines = vec![
        Line::from(""),
        Line::from(vec![
            Span::raw(format!("  Total: {total}  ")),
            Span::styled(format!("Done: {done}  "), Style::default().fg(Color::Green)),
            Span::styled(
                format!("In-Progress: {in_progress}  "),
                Style::default().fg(Color::Yellow),
            ),
        ]),
        Line::from(vec![
            Span::styled(
                format!("  Todo: {todo}  "),
                Style::default().fg(Color::Gray),
            ),
            Span::styled(
                format!("Implemented: {implemented}  "),
                Style::default().fg(Color::Cyan),
            ),
            Span::styled(
                format!("Review: {review}  "),
                Style::default().fg(Color::Magenta),
            ),
        ]),
        Line::from(vec![Span::styled(
            format!("  Blocked: {blocked}"),
            Style::default().fg(Color::Red),
        )]),
    ];

    let diagnostics = health_diagnostics(spec);
    lines.push(Line::from(""));
    lines.push(Line::from(Span::styled(
        "  Health:",
        styles::header_style(),
    )));

    if diagnostics.is_empty() {
        lines.push(Line::from(Span::styled(
            "  No issues",
            Style::default().fg(Color::Green),
        )));
    } else {
        for issue in &diagnostics {
            lines.push(Line::from(Span::styled(
                issue.as_str(),
                Style::default().fg(Color::Yellow),
            )));
        }
    }

    if !warnings.is_empty() {
        lines.push(Line::from(""));
        lines.push(Line::from(Span::styled(
            "  Parse warnings:",
            styles::header_style(),
        )));
        for w in warnings {
            lines.push(Line::from(Span::styled(
                format!("  ! {w}"),
                Style::default().fg(Color::Red),
            )));
        }
    }

    let paragraph = Paragraph::new(lines);
    frame.render_widget(paragraph, area);
}

fn health_diagnostics(spec: &Spec) -> Vec<String> {
    let in_progress = spec.count_by_status(TaskStatus::InProgress);
    let implemented = spec.count_by_status(TaskStatus::Implemented);
    let review = spec.count_by_status(TaskStatus::Review);
    let blocked = spec.count_by_status(TaskStatus::Blocked);
    let done = spec.count_by_status(TaskStatus::Done);
    let todo = spec.count_by_status(TaskStatus::Todo);
    let total = spec.tasks.len();

    let mut issues = Vec::new();
    if in_progress > 0 {
        issues.push(format!("  ! {in_progress} task(s) in-progress"));
    }
    if implemented > 0 {
        issues.push(format!("  ! {implemented} task(s) need validation"));
    }
    if review > 0 {
        issues.push(format!("  ! {review} task(s) have pending findings"));
    }
    let remaining = total.saturating_sub(done);
    if blocked == remaining && blocked > 0 && in_progress == 0 && todo == 0 {
        issues.push("  ! DEADLOCK: all remaining tasks blocked".to_string());
    }
    issues
}
