//! Locks the shared parser fixtures produced by task 001 and reused by
//! workflow-web tasks 003 (sanitizer), 005 (notify watcher), 006 (SSE). The
//! fixtures live at `tests/fixtures/parsers/`; this test fails if a fixture is
//! removed or its parse behaviour drifts, so downstream tasks can rely on a
//! stable sample set instead of re-inlining documents.

use std::fs;
use std::path::PathBuf;

use workflow_core::model::EventCategory;
use workflow_core::parse::{parse_monitor_log, parse_report, parse_task};

fn fixture(name: &str) -> String {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/parsers")
        .join(name);
    fs::read_to_string(&path).unwrap_or_else(|e| panic!("missing fixture {name}: {e}"))
}

#[test]
fn valid_task_fixture_parses() {
    // Given the shared valid task fixture
    let content = fixture("task_valid.md");
    // When parsed
    let task = parse_task(&content, "task_valid.md").unwrap();
    // Then frontmatter is decoded
    assert_eq!(task.id, "002");
    assert_eq!(task.blocked_by, vec!["001"]);
}

#[test]
fn frontmatterless_task_fixture_errors() {
    // Given the shared no-frontmatter fixture
    let content = fixture("task_no_frontmatter.md");
    // When parsed, Then it is rejected (boundary validation)
    assert!(parse_task(&content, "task_no_frontmatter.md").is_err());
}

#[test]
fn valid_report_fixture_parses() {
    let content = fixture("report_valid.yaml");
    let report = parse_report(&content, "report_valid.yaml").unwrap();
    assert_eq!(report.gate, "lint");
    assert_eq!(report.findings.len(), 1);
}

#[test]
fn monitor_fixture_covers_widened_categories_and_degrades_gracefully() {
    // Given the shared monitor fixture (known + widened + unknown + 1 bad line)
    let content = fixture("monitor_sample.jsonl");

    // When parsed
    let (events, warnings) = parse_monitor_log(&content, "monitor_sample.jsonl");

    // Then the 7 JSON lines parse (the trailing non-JSON line is the only skip)
    assert_eq!(events.len(), 7);
    assert_eq!(warnings.len(), 1, "exactly the malformed line warns");

    // And the widened [spec-review-1] categories are typed, not errors
    assert!(
        events
            .iter()
            .any(|e| e.category == EventCategory::ConfigApproved)
    );
    assert!(
        events
            .iter()
            .any(|e| e.category == EventCategory::TierApproved)
    );

    // And the unrecognised category degrades to Unknown (renderable, not dropped)
    assert!(events.iter().any(|e| e.category == EventCategory::Unknown));
}
