//! Fail-closed startup invariants (FR-23, ADR-010, SEC-FR-1, SEC-FR-22).
//! Each invariant maps to a fixed exit code: 2 bad CLI / symlink root,
//! 4 invariant violation, 7 path missing. Asserted through the real binary.

use std::process::Command;

fn bin() -> Command {
    Command::new(env!("CARGO_BIN_EXE_workflow-web"))
}

fn manifest() -> &'static str {
    env!("CARGO_MANIFEST_DIR")
}

fn fixture(name: &str) -> String {
    format!("{}/tests/fixtures/{name}", manifest())
}

fn exit_code(args: &[&str]) -> Option<i32> {
    bin().args(args).output().expect("spawn").status.code()
}

#[test]
fn missing_root_exits_7() {
    let missing = format!("{}/tests/fixtures/__does_not_exist__", manifest());
    assert_eq!(exit_code(&[&missing]), Some(7));
}

#[test]
fn root_without_projects_subdir_exits_4() {
    // `empty/` has no `projects/` child.
    assert_eq!(exit_code(&[&fixture("empty")]), Some(4));
}

#[test]
fn non_loopback_bind_exits_4() {
    assert_eq!(
        exit_code(&["--bind", "0.0.0.0", &fixture("with_projects")]),
        Some(4)
    );
}

#[test]
fn empty_allowed_host_exits_4() {
    // A single blank entry is trimmed away, leaving an empty list.
    assert_eq!(
        exit_code(&["--allowed-host", "", &fixture("with_projects")]),
        Some(4)
    );
}

#[test]
fn symlinked_root_exits_2() {
    let tmp = tempfile::tempdir().expect("tmpdir");
    let link = tmp.path().join("root-link");
    #[cfg(unix)]
    std::os::unix::fs::symlink(fixture("with_projects"), &link).expect("symlink");
    assert_eq!(
        exit_code(&[link.to_str().unwrap()]),
        Some(2),
        "a symlinked root must be rejected (SEC-FR-22)"
    );
}

/// Grep gate (SEC-FR): startup must not read any credential-shaped env var.
/// Scans the crate source for `env::var*` calls touching a forbidden suffix.
#[test]
fn no_credential_env_var_read_at_startup() {
    let src_dir = format!("{}/src", manifest());
    let forbidden = ["_TOKEN", "_KEY", "_SECRET", "_PASSWORD"];
    for entry in std::fs::read_dir(&src_dir).expect("read src/") {
        let path = entry.expect("dirent").path();
        if path.extension().and_then(|e| e.to_str()) != Some("rs") {
            continue;
        }
        let text = std::fs::read_to_string(&path).expect("read source");
        for (lineno, line) in text.lines().enumerate() {
            if line.contains("env::var") || line.contains("std::env::var") {
                let upper = line.to_uppercase();
                for needle in forbidden {
                    assert!(
                        !upper.contains(needle),
                        "{}:{} reads a credential-shaped env var: {}",
                        path.display(),
                        lineno + 1,
                        line.trim()
                    );
                }
            }
        }
    }
}
