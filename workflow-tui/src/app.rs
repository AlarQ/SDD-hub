use crate::model::Spec;
use crate::parse::scan_specs;
use std::path::PathBuf;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Panel {
    SpecList,
    DepGraph,
    Reports,
    Progress,
}

impl Panel {
    pub fn next(self) -> Self {
        match self {
            Self::SpecList => Self::DepGraph,
            Self::DepGraph => Self::Reports,
            Self::Reports => Self::Progress,
            Self::Progress => Self::SpecList,
        }
    }

    pub fn prev(self) -> Self {
        match self {
            Self::SpecList => Self::Progress,
            Self::DepGraph => Self::SpecList,
            Self::Reports => Self::DepGraph,
            Self::Progress => Self::Reports,
        }
    }
}

pub struct App {
    pub(crate) root: PathBuf,
    pub(crate) specs: Vec<Spec>,
    pub(crate) active_panel: Panel,
    pub(crate) selected_spec: usize,
    pub(crate) scroll_offset: usize,
    pub(crate) should_quit: bool,
    pub(crate) warnings: Vec<String>,
}

impl App {
    pub fn new(root: PathBuf) -> Self {
        let (specs, warnings) = scan_specs(&root);
        Self {
            root,
            specs,
            active_panel: Panel::SpecList,
            selected_spec: 0,
            scroll_offset: 0,
            should_quit: false,
            warnings,
        }
    }

    pub fn rescan(&mut self) {
        let (specs, warnings) = scan_specs(&self.root);
        self.specs = specs;
        self.warnings = warnings;
        if self.selected_spec >= self.specs.len() && !self.specs.is_empty() {
            self.selected_spec = self.specs.len() - 1;
        }
    }

    pub fn current_spec(&self) -> Option<&Spec> {
        self.specs.get(self.selected_spec)
    }

    pub fn next_panel(&mut self) {
        self.active_panel = self.active_panel.next();
        self.scroll_offset = 0;
    }

    pub fn prev_panel(&mut self) {
        self.active_panel = self.active_panel.prev();
        self.scroll_offset = 0;
    }

    pub fn scroll_down(&mut self) {
        match self.active_panel {
            Panel::SpecList => {
                if !self.specs.is_empty() && self.selected_spec < self.specs.len() - 1 {
                    self.selected_spec += 1;
                }
            }
            _ => {
                self.scroll_offset = self
                    .scroll_offset
                    .saturating_add(1)
                    .min(u16::MAX as usize);
            }
        }
    }

    pub fn scroll_up(&mut self) {
        match self.active_panel {
            Panel::SpecList => {
                self.selected_spec = self.selected_spec.saturating_sub(1);
            }
            _ => {
                self.scroll_offset = self.scroll_offset.saturating_sub(1);
            }
        }
    }

    pub fn select_spec(&mut self) {
        self.scroll_offset = 0;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{Task, TaskStatus};

    fn make_task(id: &str, status: TaskStatus) -> Task {
        Task {
            id: id.to_string(),
            name: format!("task {id}"),
            status,
            blocked_by: vec![],
            max_files: 0,
            estimated_files: vec![],
            test_cases: vec![],
            ground_rules: vec![],
        }
    }

    fn make_app(tasks: Vec<Task>) -> App {
        App {
            root: PathBuf::from("."),
            specs: vec![Spec {
                name: "test".to_string(),
                tasks,
                reports: vec![],
            }],
            active_panel: Panel::SpecList,
            selected_spec: 0,
            scroll_offset: 0,
            should_quit: false,
            warnings: vec![],
        }
    }

    #[test]
    fn panel_cycles_forward() {
        assert_eq!(Panel::SpecList.next(), Panel::DepGraph);
        assert_eq!(Panel::Progress.next(), Panel::SpecList);
    }

    #[test]
    fn panel_cycles_backward() {
        assert_eq!(Panel::SpecList.prev(), Panel::Progress);
        assert_eq!(Panel::DepGraph.prev(), Panel::SpecList);
    }

    #[test]
    fn scroll_down_clamps_to_last_spec() {
        let mut app = make_app(vec![
            make_task("001", TaskStatus::Todo),
            make_task("002", TaskStatus::Done),
        ]);
        app.specs.push(Spec {
            name: "second".to_string(),
            tasks: vec![],
            reports: vec![],
        });
        app.scroll_down(); // 0 -> 1
        app.scroll_down(); // stays at 1
        assert_eq!(app.selected_spec, 1);
    }

    #[test]
    fn scroll_up_clamps_to_zero() {
        let mut app = make_app(vec![]);
        app.scroll_up();
        assert_eq!(app.selected_spec, 0);
    }

    #[test]
    fn scroll_offset_capped_at_u16_max() {
        let mut app = make_app(vec![]);
        app.active_panel = Panel::DepGraph;
        app.scroll_offset = u16::MAX as usize;
        app.scroll_down();
        assert_eq!(app.scroll_offset, u16::MAX as usize);
    }

    #[test]
    fn next_panel_resets_scroll() {
        let mut app = make_app(vec![]);
        app.active_panel = Panel::DepGraph;
        app.scroll_offset = 10;
        app.next_panel();
        assert_eq!(app.scroll_offset, 0);
        assert_eq!(app.active_panel, Panel::Reports);
    }

    #[test]
    fn current_spec_empty() {
        let app = App {
            root: PathBuf::from("."),
            specs: vec![],
            active_panel: Panel::SpecList,
            selected_spec: 0,
            scroll_offset: 0,
            should_quit: false,
            warnings: vec![],
        };
        assert!(app.current_spec().is_none());
    }

    #[test]
    fn select_spec_resets_scroll() {
        let mut app = make_app(vec![]);
        app.scroll_offset = 5;
        app.select_spec();
        assert_eq!(app.scroll_offset, 0);
    }
}
