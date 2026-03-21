mod dep_graph;
mod layout;
mod progress;
mod reports;
mod spec_list;
mod styles;

use crate::app::{App, Panel};
use ratatui::Frame;

pub fn render(frame: &mut Frame, app: &App) {
    let chunks = layout::build_grid(frame.area());

    spec_list::render(frame, app, chunks[0], app.active_panel == Panel::SpecList);
    dep_graph::render(frame, app, chunks[1], app.active_panel == Panel::DepGraph);
    reports::render(frame, app, chunks[2], app.active_panel == Panel::Reports);
    progress::render(frame, app, chunks[3], app.active_panel == Panel::Progress);
}
