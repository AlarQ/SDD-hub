//! Lock-free shared state (ADR-009). `AppState` holds only `Arc` handles;
//! tasks own no shared mutable state beyond these. The cache (task 003) and
//! broadcast hub (task 005) are stubs at this stage — only their shape and
//! `Arc`-sharing are established here.

use crate::config::Config;
use std::sync::Arc;
use uuid::Uuid;

/// Parser cache. Stub: real `DashMap<PathBuf, CacheEntry>` lands in task 003
/// (ADR-003).
#[derive(Debug, Default)]
pub struct Cache;

impl Cache {
    pub fn new() -> Self {
        Cache
    }
}

/// Per-project SSE broadcast hub. Stub: real topic/seq/replay maps land in
/// task 005 (ADR-005). `boot_id` is established now since it is process-stable.
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

impl Default for BroadcastHub {
    fn default() -> Self {
        Self::new()
    }
}

/// Shared application state. Cloned cheaply as `Arc<AppState>` into every
/// handler and watcher.
#[derive(Debug)]
pub struct AppState {
    pub cache: Arc<Cache>,
    pub hub: Arc<BroadcastHub>,
    pub config: Arc<Config>,
}

impl AppState {
    /// Wire a validated, immutable [`Config`] into fresh stub cache + hub.
    pub fn new(config: Arc<Config>) -> Arc<Self> {
        Arc::new(AppState {
            cache: Arc::new(Cache::new()),
            hub: Arc::new(BroadcastHub::new()),
            config,
        })
    }
}
