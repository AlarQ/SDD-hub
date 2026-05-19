//! Placeholder binary — real Axum + Leptos SSR scaffold lands in task 002.
//! Touches `workflow-core` so the import boundary (workflow-core ↔
//! workflow-web seam) is exercised by the workspace build from task 001 on.

fn main() {
    // `workflow_core` is reachable from the web crate; the structural watcher
    // and handlers built in later tasks consume its `WatchSource`/parsers.
    let _: Option<workflow_core::watch::WatchEvent> = None;
    println!("workflow-web placeholder — scaffold lands in task 002");
}
