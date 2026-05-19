mod monitor;
mod reports;
mod tasks;

use self::monitor::scan_monitor_log;
use self::reports::scan_reports;
use self::tasks::scan_tasks;

use crate::model::Spec;
use crate::parse::ParseWarning;
use crate::parse::limits::MAX_SPECS;
use std::fs;
use std::path::Path;

pub fn scan_specs(root: &Path) -> (Vec<Spec>, Vec<ParseWarning>) {
    let specs_dir = root.join("specs");
    let mut specs = Vec::new();
    let mut warnings = Vec::new();

    let entries = match fs::read_dir(&specs_dir) {
        Ok(e) => e,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return (specs, warnings),
        Err(e) => {
            warnings.push(ParseWarning::FileReadError {
                path: specs_dir.display().to_string(),
                cause: e.to_string(),
            });
            return (specs, warnings);
        }
    };

    for entry in entries {
        // security-3: cap number of spec directories processed
        if specs.len() >= MAX_SPECS {
            warnings.push(ParseWarning::Truncated {
                source: specs_dir.display().to_string(),
                max: MAX_SPECS,
            });
            break;
        }

        // security-2: propagate read_dir entry errors instead of silently dropping
        let entry = match entry {
            Ok(e) => e,
            Err(e) => {
                warnings.push(ParseWarning::FileReadError {
                    path: specs_dir.display().to_string(),
                    cause: e.to_string(),
                });
                continue;
            }
        };

        // security-2: skip symlinks; default-deny on metadata failure
        if entry.file_type().map(|t| t.is_symlink()).unwrap_or(true) {
            continue;
        }
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
