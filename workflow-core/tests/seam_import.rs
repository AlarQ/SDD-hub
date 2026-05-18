//! Integration-seam test owned by task 001: the workflow-core ↔ workflow-web
//! import boundary. Proves the public surface is consumable from a downstream
//! crate and that the `WatchEvent` shape is exactly
//! `Structural{path}` / `MonitorAppend{project,feature,events}`. Compile-time
//! only — no concrete `WatchSource` impl exists yet (deferred to the web
//! consumer); runtime watch behaviour is owned by task 005.

use std::path::PathBuf;

use workflow_core::model::{EventCategory, MonitorEvent, Report, Spec, Task, TaskStatus};
use workflow_core::parse::{parse_monitor_log, parse_report, parse_task, scan_specs};
use workflow_core::watch::WatchEvent;

#[test]
fn public_parse_and_model_api_is_importable() {
    // Parsers reachable through the crate root (consumed by workflow-web only).
    let task: Task = parse_task(
        "---\nid: \"001\"\nname: t\nstatus: todo\nmax_files: 3\n---\nbody\n",
        "t.md",
    )
    .unwrap();
    assert_eq!(task.status, TaskStatus::Todo);

    let report: Report = parse_report("gate: lint\nstatus: pass\nfindings: []\n", "r.yml").unwrap();
    assert_eq!(report.gate, "lint");

    let (events, warnings) = parse_monitor_log(
        r#"{"ts":"t","category":"task_transition","feature":"f","data":{}}"#,
        "m.jsonl",
    );
    assert_eq!(events.len(), 1);
    assert_eq!(events[0].category, EventCategory::TaskTransition);
    assert!(warnings.is_empty());

    // `scan_specs` + `Spec` are part of the boundary surface.
    let _scan: fn(&std::path::Path) -> (Vec<Spec>, _) = scan_specs;
}

#[test]
fn watch_event_shape_is_structural_and_monitor_append() {
    let _structural = WatchEvent::Structural {
        path: PathBuf::from("projects/p/specs/f/spec.md"),
    };
    let ev = MonitorEvent {
        ts: "t".into(),
        category: EventCategory::Unknown,
        task: None,
        feature: "f".into(),
        correlation_id: None,
        data: serde_json::Value::Null,
    };
    let _append = WatchEvent::MonitorAppend {
        project: "p".into(),
        feature: "f".into(),
        events: vec![ev],
    };
}
