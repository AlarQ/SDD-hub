mod dep_graph;
mod layout;
mod monitor;
mod progress;
mod reports;
mod spec_list;
mod styles;

use crate::app::{App, Panel};
use ratatui::Frame;

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

    let events = app
        .current_spec()
        .map(|s| s.monitor_events.as_slice())
        .unwrap_or(&[]);
    monitor::render(
        frame,
        events,
        dashboard.grid[3],
        app.active_panel == Panel::Monitor,
        app.scroll_offset,
    );
}
