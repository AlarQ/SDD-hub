mod monitor_event;
mod report;
mod spec;
mod task;

pub use monitor_event::{EventCategory, MonitorEvent};
pub use report::Report;
pub use spec::Spec;
pub use task::{Task, TaskStatus};
// Re-exported for tests / external consumers; the binary reaches interaction
// state through `Task` methods, so the name itself is otherwise unused here.
#[allow(unused_imports)]
pub use task::Interaction;
