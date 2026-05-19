//! CLI surface + happy-path lifecycle (FR-22, ADR-010). Drives the compiled
//! binary so the exact process boundary the user hits is exercised.

use std::io::{Read, Write};
use std::net::TcpStream;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

fn bin() -> Command {
    Command::new(env!("CARGO_BIN_EXE_workflow-web"))
}

fn fixture(name: &str) -> String {
    format!("{}/tests/fixtures/{name}", env!("CARGO_MANIFEST_DIR"))
}

#[test]
fn help_lists_every_flag() {
    let out = bin().arg("--help").output().expect("spawn --help");
    assert!(out.status.success(), "--help must exit 0");
    let help = String::from_utf8_lossy(&out.stdout);
    for flag in ["--bind", "--port", "--allowed-host", "--log"] {
        assert!(help.contains(flag), "--help missing {flag}:\n{help}");
    }
    // Positional root is documented too.
    assert!(
        help.to_lowercase().contains("root"),
        "help missing root arg"
    );
}

#[test]
fn malformed_args_exit_2() {
    let out = bin()
        .args(["--port", "not-a-number", &fixture("with_projects")])
        .output()
        .expect("spawn bad args");
    assert_eq!(
        out.status.code(),
        Some(2),
        "clap parse failure must be exit 2"
    );
}

/// Wait until `addr` accepts a TCP connection or `deadline` elapses.
fn wait_listening(addr: &str, deadline: Duration) -> bool {
    let start = Instant::now();
    while start.elapsed() < deadline {
        if TcpStream::connect(addr).is_ok() {
            return true;
        }
        std::thread::sleep(Duration::from_millis(25));
    }
    false
}

#[test]
fn valid_invocation_binds_serves_404_and_shuts_down_on_sigint() {
    // A non-default port keeps parallel test runs / a stray 8787 from colliding.
    let port = "8791";
    let addr = format!("127.0.0.1:{port}");
    let mut child = bin()
        .args(["--port", port, &fixture("with_projects")])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .expect("spawn server");

    assert!(
        wait_listening(&addr, Duration::from_secs(10)),
        "server never bound {addr}"
    );

    // Raw HTTP/1.1 GET / — the router is empty, so any path is 404.
    let mut sock = TcpStream::connect(&addr).expect("connect");
    sock.write_all(b"GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
        .expect("write request");
    let mut resp = String::new();
    sock.read_to_string(&mut resp).expect("read response");
    assert!(
        resp.starts_with("HTTP/1.1 404"),
        "empty router must 404, got:\n{resp}"
    );

    // SIGINT → graceful shutdown → exit 0.
    let status = Command::new("kill")
        .args(["-INT", &child.id().to_string()])
        .status()
        .expect("send SIGINT");
    assert!(status.success(), "kill -INT failed");

    let start = Instant::now();
    let code = loop {
        if let Some(s) = child.try_wait().expect("try_wait") {
            break s.code();
        }
        if start.elapsed() > Duration::from_secs(10) {
            let _ = child.kill();
            panic!("server did not exit after SIGINT");
        }
        std::thread::sleep(Duration::from_millis(25));
    };
    assert_eq!(code, Some(0), "graceful shutdown must exit 0");
}
