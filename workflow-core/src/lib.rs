//! `workflow-core` — shared model + parsing library for the workflow web
//! dashboard. Harvested from the prior terminal-UI crate (model + parse),
//! plus the `WatchSource`/`WatchEvent` surface consumed by `workflow-web`.
//!
//! No terminal-UI or web-only code lives here: the crate builds standalone
//! (`cargo check -p workflow-core`).

pub mod model;
pub mod parse;
pub mod watch;
