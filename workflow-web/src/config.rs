//! CLI surface (FR-22) + fail-closed startup validation (FR-23, ADR-010,
//! SEC-FR-1, SEC-FR-22). All invariants run *before* any socket binds.

use clap::Parser;
use std::net::IpAddr;
use std::path::PathBuf;

/// Clap-derive CLI (FR-22). Parse failure / `--help` are handled by clap,
/// which exits with code 2 on bad args and 0 on `--help`/`--version`.
#[derive(Parser, Debug, Clone)]
#[command(
    name = "workflow-web",
    about = "Read-only web dashboard for spec-driven workflow status"
)]
pub struct Cli {
    /// Master-brain root (must contain a `projects/` subdir).
    pub root: PathBuf,

    /// Bind address — must be loopback (SEC-FR-1).
    #[arg(long, default_value = "127.0.0.1")]
    pub bind: IpAddr,

    /// TCP port.
    #[arg(long, default_value_t = 8787)]
    pub port: u16,

    /// Allowed Host header value (repeatable). Empty list fails closed.
    #[arg(
        long = "allowed-host",
        default_values_t = [
            String::from("localhost"),
            String::from("127.0.0.1"),
            String::from("[::1]"),
        ]
    )]
    pub allowed_host: Vec<String>,

    /// Log level.
    #[arg(long, default_value = "info")]
    pub log: tracing::Level,
}

/// Startup failure carrying its ADR-010 exit code.
///
/// Exit codes: `0` ok, `2` bad CLI / unreadable / symlink root, `4` invariant
/// fail, `7` path missing.
#[derive(Debug, thiserror::Error)]
pub enum StartupError {
    #[error("path missing: {0}")]
    PathMissing(String),
    #[error("invariant violation: {0}")]
    Invariant(String),
    #[error("bad CLI: {0}")]
    BadCli(String),
}

impl StartupError {
    pub fn exit_code(&self) -> i32 {
        match self {
            StartupError::BadCli(_) => 2,
            StartupError::Invariant(_) => 4,
            StartupError::PathMissing(_) => 7,
        }
    }
}

/// Immutable, validated runtime config. Constructed once at boot via
/// [`Config::from_cli`]; never mutated thereafter (shared as `Arc<Config>`).
#[derive(Debug, Clone)]
pub struct Config {
    root: PathBuf,
    bind: IpAddr,
    port: u16,
    allowed_host: Vec<String>,
    log: tracing::Level,
}

impl Config {
    /// Validate every startup invariant *before* returning. Order matters: a
    /// missing root is `7`, a symlinked/unreadable root is `2`, every other
    /// invariant is `4`. The root is canonicalized exactly once here
    /// (SEC-FR-22) and stored absolute.
    pub fn from_cli(cli: Cli) -> Result<Self, StartupError> {
        // (a) root must exist. `symlink_metadata` does not follow links, so a
        //     missing path errors here -> exit 7 (path missing).
        let meta = std::fs::symlink_metadata(&cli.root)
            .map_err(|e| StartupError::PathMissing(format!("root: {e}")))?;

        // (b) a root that is *itself* a symlink is rejected at canonicalize
        //     time -> exit 2 (SEC-FR-22). NOTE: a symlink *inside* the tree
        //     that escapes root is task 004's path-guard concern, not retested
        //     here.
        if meta.file_type().is_symlink() {
            return Err(StartupError::BadCli("root is a symlink".into()));
        }

        // (c) canonicalize once; unreadable -> exit 2.
        let root = std::fs::canonicalize(&cli.root)
            .map_err(|e| StartupError::BadCli(format!("root canonicalize: {e}")))?;

        // (c2) Ancestor-symlink guard (SEC-FR-22): compare the canonical path
        //      against the lexically-cleaned input (no FS calls).  If they
        //      differ, at least one ancestor component is a symlink that was
        //      silently resolved by canonicalize(); reject fail-fast.
        let lexical = lexical_clean(&cli.root);
        if root != lexical {
            return Err(StartupError::BadCli(
                "root path contains a symlinked ancestor component".into(),
            ));
        }

        if !root.is_dir() {
            return Err(StartupError::Invariant("root is not a directory".into()));
        }

        // (d) root/projects/ must exist (FR-23).
        if !root.join("projects").is_dir() {
            return Err(StartupError::Invariant("root/projects/ missing".into()));
        }

        // (e) bind addr must be loopback (SEC-FR-1).
        if !cli.bind.is_loopback() {
            return Err(StartupError::Invariant(format!(
                "bind {} is not loopback",
                cli.bind
            )));
        }

        // (f) allowed-host list non-empty after dropping blanks (FR-23).
        let allowed_host: Vec<String> = cli
            .allowed_host
            .into_iter()
            .filter(|h| !h.trim().is_empty())
            .collect();
        if allowed_host.is_empty() {
            return Err(StartupError::Invariant("allowed-host list is empty".into()));
        }

        Ok(Config {
            root,
            bind: cli.bind,
            port: cli.port,
            allowed_host,
            log: cli.log,
        })
    }

    pub fn root(&self) -> &std::path::Path {
        &self.root
    }
    pub fn bind(&self) -> IpAddr {
        self.bind
    }
    pub fn port(&self) -> u16 {
        self.port
    }
    pub fn allowed_host(&self) -> &[String] {
        &self.allowed_host
    }
    pub fn log(&self) -> tracing::Level {
        self.log
    }
    pub fn socket_addr(&self) -> std::net::SocketAddr {
        std::net::SocketAddr::new(self.bind, self.port)
    }
}

/// Lexically clean `path` without any filesystem calls: make absolute (using
/// CWD if relative), then resolve `.` and `..` components in order.
/// The result is used only for comparison against the canonical path; no FS
/// access happens here.
fn lexical_clean(path: &std::path::Path) -> PathBuf {
    use std::path::Component;

    let abs: std::borrow::Cow<std::path::Path> = if path.is_absolute() {
        std::borrow::Cow::Borrowed(path)
    } else {
        // Fallback: if CWD is unavailable, return the path unchanged so the
        // comparison can still work (canonicalize will also have the CWD).
        match std::env::current_dir() {
            Ok(cwd) => std::borrow::Cow::Owned(cwd.join(path)),
            Err(_) => std::borrow::Cow::Borrowed(path),
        }
    };

    let mut out = PathBuf::new();
    for component in abs.components() {
        match component {
            Component::CurDir => {}
            Component::ParentDir => {
                out.pop();
            }
            c => out.push(c),
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Verifies that a root path whose *parent* directory is a symlink is
    /// rejected by the ancestor-symlink guard (SEC-FR-22 / step c2).
    ///
    /// Layout:
    ///   <base>/real_parent/vault/           <- the actual vault directory
    ///   <base>/real_parent/vault/projects/  <- required subdir
    ///   <base>/link_parent -> real_parent   <- symlinked ancestor (not the leaf)
    ///
    /// We pass `<base>/link_parent/vault` as root.  The leaf (`vault`) is NOT
    /// a symlink — step (b) does not fire.  Step (c2) detects that
    /// canonicalize resolves `link_parent` to `real_parent`, making the
    /// canonical path differ from the lexically-cleaned input.
    #[test]
    fn rejects_symlinked_ancestor() {
        use std::os::unix::fs::symlink;

        let base = tempfile::tempdir().expect("tempdir");
        let real_parent = base.path().join("real_parent");
        let vault = real_parent.join("vault");
        std::fs::create_dir_all(vault.join("projects")).unwrap();

        // link_parent is a symlink -> real_parent (ancestor symlink)
        let link_parent = base.path().join("link_parent");
        symlink(&real_parent, &link_parent).expect("symlink");

        // root path goes *through* the symlinked ancestor
        let root_via_symlink = link_parent.join("vault");
        // Sanity: the leaf itself must not be a symlink
        assert!(
            !root_via_symlink
                .symlink_metadata()
                .unwrap()
                .file_type()
                .is_symlink(),
            "leaf must not be a symlink for this test to exercise c2"
        );

        let cli = Cli {
            root: root_via_symlink,
            bind: "127.0.0.1".parse().unwrap(),
            port: 8787,
            allowed_host: vec!["localhost".into(), "127.0.0.1".into(), "[::1]".into()],
            log: tracing::Level::INFO,
        };

        let result = Config::from_cli(cli);
        assert!(
            matches!(result, Err(StartupError::BadCli(ref msg)) if msg.contains("symlink")),
            "expected BadCli(symlink ancestor), got: {result:?}"
        );
    }
}
