mod dep_graph;
mod layout;
mod progress;
mod reports;
mod spec_list;
mod styles;

use crate::app::{App, Panel};
use ratatui::Frame;
use ratatui::widgets::{Block, Borders, Paragraph};

pub fn render(frame: &mut Frame, app: &App) {
    let dashboard = layout::build_layout(frame.area());

    spec_list::render(
        frame,
        app,
        dashboard.sidebar,
        app.active_panel == Panel::SpecList,
    );
    dep_graph::render(
        frame,
        app,
        dashboard.grid[0],
        app.active_panel == Panel::DepGraph,
    );
    reports::render(
        frame,
        app,
        dashboard.grid[1],
        app.active_panel == Panel::Reports,
    );
    progress::render(
        frame,
        app,
        dashboard.grid[2],
        app.active_panel == Panel::Progress,
    );
    render_monitor_placeholder(frame, dashboard.grid[3], app.active_panel == Panel::Monitor);
}

fn render_monitor_placeholder(frame: &mut Frame, area: ratatui::layout::Rect, active: bool) {
    let block = Block::default()
        .title(" Monitor ")
        .borders(Borders::ALL)
        .border_style(styles::panel_border(active));
    let p = Paragraph::new("  Monitor panel — coming in task 006").block(block);
    frame.render_widget(p, area);
}
