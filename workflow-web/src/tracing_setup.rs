//! Tracing subscriber wiring. The fmt layer writes through
//! [`RedactingWriter`] so no secret reaches the sink (SEC-FR-19).

use crate::tracing_redact::RedactingWriter;
use std::io;
use tracing::Level;
use tracing_subscriber::fmt::MakeWriter;

/// `MakeWriter` yielding a redacting wrapper around stderr for every event.
#[derive(Clone, Default)]
pub struct RedactingMakeWriter;

impl<'a> MakeWriter<'a> for RedactingMakeWriter {
    type Writer = RedactingWriter<io::Stderr>;
    fn make_writer(&'a self) -> Self::Writer {
        RedactingWriter::new(io::stderr())
    }
}

/// Install the global subscriber at `level`. Idempotent-safe: a second call
/// (e.g. in tests) is ignored rather than panicking.
pub fn init(level: Level) {
    let _ = tracing_subscriber::fmt()
        .with_max_level(level)
        .with_writer(RedactingMakeWriter)
        .with_target(false)
        .try_init();
}
