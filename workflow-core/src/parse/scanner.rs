use crate::model::Spec;
use crate::parse::{ParseWarning, parse_monitor_log, parse_report, parse_task};
use std::fs;
use std::io::{BufRead, BufReader};
use std::path::Path;

const MAX_FILE_BYTES: u64 = 8 * 1024 * 1024;
const MAX_EVENTS: usize = 10_000;

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

    for entry in entries.flatten() {
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

fn scan_tasks(dir: &Path) -> (Vec<crate::model::Task>, Vec<ParseWarning>) {
    let mut tasks = Vec::new();
    let mut warnings = Vec::new();
    let entries = match fs::read_dir(dir) {
        Ok(e) => e,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return (tasks, warnings),
        Err(e) => {
            warnings.push(ParseWarning::FileReadError {
                path: dir.display().to_string(),
                cause: e.to_string(),
            });
            return (tasks, warnings);
        }
    };

    for entry in entries.flatten() {
        // security-2: skip symlinks; default-deny on metadata failure
        if entry.file_type().map(|t| t.is_symlink()).unwrap_or(true) {
            continue;
        }
        let path = entry.path();
        if path.extension().is_none_or(|e| e != "md") {
            continue;
        }

        // security-1: size cap before reading
        let file_len = entry.metadata().map(|m| m.len()).unwrap_or(u64::MAX);
        if file_len > MAX_FILE_BYTES {
            warnings.push(ParseWarning::FileReadError {
                path: path.display().to_string(),
                cause: format!("file exceeds size limit ({file_len} > {MAX_FILE_BYTES})"),
            });
            continue;
        }

        // cqp-7: no let-chain — explicit let-else form
        let Ok(content) = fs::read_to_string(&path) else {
            continue;
        };

        match parse_task(&content, &path.to_string_lossy()) {
            Ok(task) => tasks.push(task),
            Err(e) => warnings.push(ParseWarning::FileReadError {
                path: path.display().to_string(),
                cause: format!("{e:#}"),
            }),
        }
    }

    tasks.sort_by(|a, b| a.id.cmp(&b.id));
    (tasks, warnings)
}

fn scan_monitor_log(spec_dir: &Path) -> (Vec<crate::model::MonitorEvent>, Vec<ParseWarning>) {
    let monitor_file = spec_dir.join(".monitor.jsonl");

    // security-1: use BufReader line reader capped at MAX_EVENTS lines
    let file = match fs::File::open(&monitor_file) {
        Ok(f) => f,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return (Vec::new(), Vec::new()),
        Err(e) => {
            return (
                Vec::new(),
                vec![ParseWarning::FileReadError {
                    path: monitor_file.display().to_string(),
                    cause: e.to_string(),
                }],
            );
        }
    };

    let reader = BufReader::new(file);
    let mut capped_content = String::new();
    let mut truncated = false;
    for (i, line) in reader.lines().enumerate() {
        match line {
            Ok(l) => {
                if i >= MAX_EVENTS {
                    truncated = true;
                    break;
                }
                capped_content.push_str(&l);
                capped_content.push('\n');
            }
            Err(e) => {
                return (
                    Vec::new(),
                    vec![ParseWarning::FileReadError {
                        path: monitor_file.display().to_string(),
                        cause: e.to_string(),
                    }],
                );
            }
        }
    }

    let (events, mut warnings) =
        parse_monitor_log(&capped_content, &monitor_file.to_string_lossy());

    if truncated {
        warnings.push(ParseWarning::Truncated {
            source: monitor_file.display().to_string(),
            max: MAX_EVENTS,
        });
    }

    (events, warnings)
}

fn scan_reports(dir: &Path) -> (Vec<crate::model::Report>, Vec<ParseWarning>) {
    let mut reports = Vec::new();
    let mut warnings = Vec::new();
    let entries = match fs::read_dir(dir) {
        Ok(e) => e,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return (reports, warnings),
        Err(e) => {
            warnings.push(ParseWarning::FileReadError {
                path: dir.display().to_string(),
                cause: e.to_string(),
            });
            return (reports, warnings);
        }
    };

    for entry in entries.flatten() {
        // security-2: skip symlinks; default-deny on metadata failure
        if entry.file_type().map(|t| t.is_symlink()).unwrap_or(true) {
            continue;
        }
        let path = entry.path();
        if !path.extension().is_some_and(|e| e == "yaml" || e == "yml") {
            continue;
        }

        // security-1: size cap before reading
        let file_len = entry.metadata().map(|m| m.len()).unwrap_or(u64::MAX);
        if file_len > MAX_FILE_BYTES {
            warnings.push(ParseWarning::FileReadError {
                path: path.display().to_string(),
                cause: format!("file exceeds size limit ({file_len} > {MAX_FILE_BYTES})"),
            });
            continue;
        }

        // cqp-7: no let-chain — explicit let-else form
        let Ok(content) = fs::read_to_string(&path) else {
            continue;
        };

        match parse_report(&content, &path.to_string_lossy()) {
            Ok(report) => reports.push(report),
            Err(e) => warnings.push(ParseWarning::FileReadError {
                path: path.display().to_string(),
                cause: format!("{e:#}"),
            }),
        }
    }

    (reports, warnings)
}
