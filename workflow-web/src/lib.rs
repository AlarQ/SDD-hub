//! `workflow-web` — read-only Axum + Leptos SSR dashboard for spec-driven
//! workflow status. This module exposes the scaffold seams (CLI → Config →
//! AppState → Router) so integration tests can exercise them without the
//! process boundary. HTTP handlers, cache, watchers and SSE land in later
//! tasks; the router is intentionally empty here (any path → 404).

pub mod app_state;
pub mod config;
pub mod error;
pub mod tracing_redact;
pub mod tracing_setup;

use app_state::AppState;
use axum::Router;
use clap::Parser;
use config::{Cli, Config};
use std::sync::Arc;

/// Build the shared state + (empty) router from a validated config. The router
/// carries `Arc<AppState>` so later tasks bolt handlers onto a wired seam.
pub fn build_app(config: Arc<Config>) -> (Arc<AppState>, Router) {
    let state = AppState::new(config);
    let router = Router::new().with_state(state.clone());
    (state, router)
}

/// Bind the loopback socket and serve until SIGINT (Ctrl-C), then shut down
/// gracefully. The socket is bound *after* config validation by construction —
/// callers pass an already-validated [`Config`].
pub async fn serve(config: Arc<Config>) -> anyhow::Result<()> {
    let addr = config.socket_addr();
    let (_state, router) = build_app(config);
    let listener = tokio::net::TcpListener::bind(addr).await?;
    tracing::info!("listening on {addr}");
    axum::serve(listener, router)
        .with_graceful_shutdown(shutdown_signal())
        .await?;
    Ok(())
}

async fn shutdown_signal() {
    let _ = tokio::signal::ctrl_c().await;
    tracing::info!("SIGINT received — shutting down");
}

/// Full process entrypoint: parse → validate → init logging → serve.
/// Returns the process exit code (0 ok; 2/4/7 per ADR-010 on startup failure).
pub async fn run() -> i32 {
    let cli = Cli::parse_from(std::env::args_os());
    let level = cli.log;
    let config = match Config::from_cli(cli) {
        Ok(c) => Arc::new(c),
        Err(e) => {
            // Logging is not up yet — write the (non-secret) reason to stderr.
            eprintln!("startup error: {e}");
            return e.exit_code();
        }
    };
    tracing_setup::init(level);
    match serve(config).await {
        Ok(()) => 0,
        Err(e) => {
            tracing::error!("serve error: {e}");
            1
        }
    }
}

#[cfg(test)]
mod seam_tests {
    use super::*;

    fn valid_config() -> Arc<Config> {
        // Repo-relative fixture with a real `projects/` subtree.
        let root = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/with_projects");
        let cli = Cli::parse_from(["workflow-web", root]);
        Arc::new(Config::from_cli(cli).expect("fixture is a valid root"))
    }

    #[test]
    fn appstate_exposes_cache_hub_config() {
        let cfg = valid_config();
        let state = AppState::new(cfg.clone());
        // Fields are plain owned values inside the outer Arc<AppState>.
        let _boot = state.hub.boot_id();
        assert!(Arc::strong_count(&state.config) >= 1);
        // Config is the same validated, immutable instance.
        assert_eq!(state.config.root(), cfg.root());
    }

    #[test]
    fn cli_to_appstate_seam_wires_config_into_router() {
        let cfg = valid_config();
        let root = cfg.root().to_owned();
        let (state, _router) = build_app(cfg);
        // The served router holds an AppState carrying the validated config:
        // the CLI ↔ AppState seam is connected end to end.
        assert_eq!(state.config.root(), root);
        assert_eq!(state.config.port(), 8787);
        assert!(state.config.bind().is_loopback());
    }
}
