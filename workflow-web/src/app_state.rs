//! Lock-free shared state (ADR-009). `AppState` is wrapped in `Arc` by callers;
//! its fields are plain owned values — no double-Arc nesting. The cache (task 003)
//! and broadcast hub (task 005) are stubs at this stage — only their shape is
//! established here.

use crate::config::Config;
use std::sync::Arc;
use uuid::Uuid;

/// Parser cache. Stub: real `DashMap<PathBuf, CacheEntry>` lands in task 003
/// (ADR-003). Use `Cache::default()` to construct.
#[derive(Debug, Default)]
pub struct Cache;

/// Per-project SSE broadcast hub. Stub: real topic/seq/replay maps land in
/// task 005 (ADR-005). `boot_id` is established now since it is process-stable.
/// `Default` is intentionally omitted — each `new()` generates a unique boot_id.
#[derive(Debug)]
pub struct BroadcastHub {
    boot_id: Uuid,
}

impl BroadcastHub {
    pub fn new() -> Self {
        BroadcastHub {
            boot_id: Uuid::new_v4(),
        }
    }
    pub fn boot_id(&self) -> Uuid {
        self.boot_id
    }
}

/// Shared application state. Cloned cheaply as `Arc<AppState>` into every
/// handler and watcher.
#[derive(Debug)]
pub struct AppState {
    pub cache: Cache,
    pub hub: BroadcastHub,
    pub config: Arc<Config>,
}

impl AppState {
    /// Wire a validated, immutable [`Config`] into fresh stub cache + hub.
    pub fn new(config: Arc<Config>) -> Arc<Self> {
        Arc::new(AppState {
            cache: Cache::default(),
            hub: BroadcastHub::new(),
            config,
        })
    }
}
