use crate::model::Spec;
use crate::parse::{ParseWarning, parse_monitor_log, parse_report, parse_task};
use std::fs;
use std::path::Path;

pub fn scan_specs(root: &Path) -> (Vec<Spec>, Vec<ParseWarning>) {
    let specs_dir = root.join("specs");
    let mut specs = Vec::new();
    let mut warnings = Vec::new();

    let entries = match fs::read_dir(&specs_dir) {
        Ok(e) => e,
        Err(_) => return (specs, warnings),
    };

    for entry in entries.flatten() {
        let path = entry.path();
        if !path.is_dir() {
            continue;
        }

        let name = path
            .file_name()
            .map(|n| n.to_string_lossy().to_string())
            .unwrap_or_default();

        let (tasks, task_warns) = scan_tasks(&path.join("tasks"));
        let (reports, report_warns) = scan_reports(&path.join("reports"));
        let (monitor_events, monitor_warns) = scan_monitor_log(&path);
        warnings.extend(task_warns);
        warnings.extend(report_warns);
        warnings.extend(monitor_warns);

        specs.push(Spec {
            name,
            tasks,
            reports,
            monitor_events,
        });
    }

    specs.sort_by(|a, b| a.name.cmp(&b.name));
    (specs, warnings)
}

fn scan_tasks(dir: &Path) -> (Vec<crate::model::Task>, Vec<ParseWarning>) {
    let mut tasks = Vec::new();
    let mut warnings = Vec::new();
    let entries = match fs::read_dir(dir) {
        Ok(e) => e,
        Err(_) => return (tasks, warnings),
    };

    for entry in entries.flatten() {
        let path = entry.path();
        if path.extension().is_some_and(|e| e == "md")
            && let Ok(content) = fs::read_to_string(&path)
        {
            match parse_task(&content, &path.to_string_lossy()) {
                Ok(task) => tasks.push(task),
                Err(e) => warnings.push(ParseWarning::FileReadError {
                    path: path.display().to_string(),
                    cause: format!("{e:#}"),
                }),
            }
        }
    }

    tasks.sort_by(|a, b| a.id.cmp(&b.id));
    (tasks, warnings)
}

fn scan_monitor_log(spec_dir: &Path) -> (Vec<crate::model::MonitorEvent>, Vec<ParseWarning>) {
    let monitor_file = spec_dir.join(".monitor.jsonl");
    match fs::read_to_string(&monitor_file) {
        Ok(content) => parse_monitor_log(&content, &monitor_file.to_string_lossy()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => (Vec::new(), Vec::new()),
        Err(e) => (
            Vec::new(),
            vec![ParseWarning::FileReadError {
                path: monitor_file.display().to_string(),
                cause: e.to_string(),
            }],
        ),
    }
}

fn scan_reports(dir: &Path) -> (Vec<crate::model::Report>, Vec<ParseWarning>) {
    let mut reports = Vec::new();
    let mut warnings = Vec::new();
    let entries = match fs::read_dir(dir) {
        Ok(e) => e,
        Err(_) => return (reports, warnings),
    };

    for entry in entries.flatten() {
        let path = entry.path();
        let is_yaml = path.extension().is_some_and(|e| e == "yaml" || e == "yml");
        if is_yaml && let Ok(content) = fs::read_to_string(&path) {
            match parse_report(&content, &path.to_string_lossy()) {
                Ok(report) => reports.push(report),
                Err(e) => warnings.push(ParseWarning::FileReadError {
                    path: path.display().to_string(),
                    cause: format!("{e:#}"),
                }),
            }
        }
    }

    (reports, warnings)
}
