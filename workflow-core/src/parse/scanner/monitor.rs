use crate::model::MonitorEvent;
use crate::parse::limits::MAX_EVENTS;
use crate::parse::{ParseWarning, parse_monitor_log};
use std::fs;
use std::io::{BufRead, BufReader};
use std::path::Path;

pub(super) fn scan_monitor_log(spec_dir: &Path) -> (Vec<MonitorEvent>, Vec<ParseWarning>) {
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
