use crate::model::Report;
use crate::parse::limits::MAX_FILE_BYTES;
use crate::parse::{ParseWarning, parse_report};
use std::fs;
use std::path::Path;

pub(super) fn scan_reports(dir: &Path) -> (Vec<Report>, Vec<ParseWarning>) {
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

    for entry in entries {
        let entry = match entry {
            Ok(e) => e,
            Err(e) => {
                warnings.push(ParseWarning::FileReadError {
                    path: dir.display().to_string(),
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
