use crate::model::Spec;
use crate::parse::{parse_report, parse_task};
use std::fs;
use std::path::Path;

pub fn scan_specs(root: &Path) -> (Vec<Spec>, Vec<String>) {
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
        warnings.extend(task_warns);
        warnings.extend(report_warns);

        specs.push(Spec {
            name,
            tasks,
            reports,
        });
    }

    specs.sort_by(|a, b| a.name.cmp(&b.name));
    (specs, warnings)
}

fn scan_tasks(dir: &Path) -> (Vec<crate::model::Task>, Vec<String>) {
    let mut tasks = Vec::new();
    let mut warnings = Vec::new();
    let entries = match fs::read_dir(dir) {
        Ok(e) => e,
        Err(_) => return (tasks, warnings),
    };

    for entry in entries.flatten() {
        let path = entry.path();
        if path.extension().is_some_and(|e| e == "md") {
            if let Ok(content) = fs::read_to_string(&path) {
                match parse_task(&content, &path.to_string_lossy()) {
                    Ok(task) => tasks.push(task),
                    Err(e) => warnings.push(format!("{}: {e:#}", path.display())),
                }
            }
        }
    }

    tasks.sort_by(|a, b| a.id.cmp(&b.id));
    (tasks, warnings)
}

fn scan_reports(dir: &Path) -> (Vec<crate::model::Report>, Vec<String>) {
    let mut reports = Vec::new();
    let mut warnings = Vec::new();
    let entries = match fs::read_dir(dir) {
        Ok(e) => e,
        Err(_) => return (reports, warnings),
    };

    for entry in entries.flatten() {
        let path = entry.path();
        let is_yaml = path
            .extension()
            .is_some_and(|e| e == "yaml" || e == "yml");
        if is_yaml {
            if let Ok(content) = fs::read_to_string(&path) {
                match parse_report(&content, &path.to_string_lossy()) {
                    Ok(report) => reports.push(report),
                    Err(e) => warnings.push(format!("{}: {e:#}", path.display())),
                }
            }
        }
    }

    (reports, warnings)
}
