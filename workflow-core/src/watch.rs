//! Watch surface (ADR-001). New abstraction — **no concrete impl in this
//! crate**. The `workflow-web` crate provides the only `WatchSource`
//! implementation (notify-backed) in later tasks. `workflow-core` owns the
//! trait + event shape so the emitted models stay co-located with the watcher
//! contract.

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

/// A source of [`WatchEvent`]s. Concrete (notify-backed) implementations live
/// in the `workflow-web` consumer; `workflow-core` defines only the contract.
pub trait WatchSource {
    /// Block until the next watch event is available, or return `None` once
    /// the source is exhausted/closed. `Err` is a fatal watcher failure.
    fn next_event(&mut self) -> anyhow::Result<Option<WatchEvent>>;
}
