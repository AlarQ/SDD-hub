//! Watch surface (ADR-001). `workflow-core` owns the event shape so the
//! emitted models stay co-located with the rest of the domain. The async
//! watcher contract (tokio + notify) will be defined in task 005 once the
//! real interface requirements are known.

use std::path::PathBuf;

use crate::model::MonitorEvent;

/// A filesystem change relevant to the dashboard.
///
/// `Structural` carries only the raw path; the structural watcher (in the web
/// consumer) is responsible for extracting `(project, feature)` before
/// publishing to the broadcast hub. `MonitorAppend` is already enriched
/// because the tail watcher knows which monitor file it is reading.
#[derive(Debug, Clone)]
pub enum WatchEvent {
    Structural {
        path: PathBuf,
    },
    MonitorAppend {
        project: String,
        feature: String,
        events: Vec<MonitorEvent>,
    },
}
