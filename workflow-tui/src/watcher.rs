use anyhow::Result;
use notify_debouncer_mini::{new_debouncer, DebouncedEventKind};
use std::path::Path;
use std::sync::mpsc;
use std::time::Duration;

/// Start watching `specs/` dir. Returns a receiver that gets a signal on file changes.
/// The debouncer is returned to keep it alive — drop it to stop watching.
pub fn start_watcher(
    root: &Path,
) -> Result<(
    mpsc::Receiver<()>,
    notify_debouncer_mini::Debouncer<notify::RecommendedWatcher>,
)> {
    let specs_dir = root.join("specs");
    let (tx, rx) = mpsc::channel();

    let mut debouncer = new_debouncer(
        Duration::from_millis(500),
        move |res: Result<Vec<notify_debouncer_mini::DebouncedEvent>, notify::Error>| {
            if let Ok(events) = res {
                let has_changes = events.iter().any(|e| e.kind == DebouncedEventKind::Any);
                if has_changes {
                    let _ = tx.send(());
                }
            }
        },
    )?;

    debouncer
        .watcher()
        .watch(&specs_dir, notify::RecursiveMode::Recursive)?;

    Ok((rx, debouncer))
}
