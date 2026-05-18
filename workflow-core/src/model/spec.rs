use super::monitor_event::MonitorEvent;
use super::report::Report;
use super::task::{Task, TaskStatus};

#[derive(Debug, Clone)]
pub struct Spec {
    pub name: String,
    pub tasks: Vec<Task>,
    pub reports: Vec<Report>,
    pub monitor_events: Vec<MonitorEvent>,
}

impl Spec {
    pub fn progress_percent(&self) -> u16 {
        if self.tasks.is_empty() {
            return 0;
        }
        let done = self.count_by_status(TaskStatus::Done);
        ((done as f64 / self.tasks.len() as f64) * 100.0) as u16
    }

    pub fn count_by_status(&self, status: TaskStatus) -> usize {
        self.tasks.iter().filter(|t| t.status == status).count()
    }
}
