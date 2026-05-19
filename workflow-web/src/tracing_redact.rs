//! Secret redaction for log output (SEC-FR-19). Every byte written by the
//! tracing subscriber passes through [`redact`] before hitting the sink, so a
//! secret accidentally placed in a span field / message is scrubbed regardless
//! of which layer emitted it.

use regex::Regex;
use std::io::{self, Write};
use std::sync::OnceLock;

const PLACEHOLDER: &str = "[REDACTED]";

struct Patterns {
    set: Vec<Regex>,
}

fn patterns() -> &'static Patterns {
    static P: OnceLock<Patterns> = OnceLock::new();
    P.get_or_init(|| Patterns {
        set: vec![
            // OpenAI: sk-... (also sk-proj-...)
            Regex::new(r"sk-[A-Za-z0-9_-]{16,}").unwrap(),
            // GitHub PAT family: ghp_, gho_, ghu_, ghs_, ghr_
            Regex::new(r"gh[poursa]_[A-Za-z0-9]{20,}").unwrap(),
            // Slack: xoxb-/xoxa-/xoxp-/xoxr-...
            Regex::new(r"xox[baprs]-[A-Za-z0-9-]{8,}").unwrap(),
            // JWT: three base64url segments
            Regex::new(r"eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+").unwrap(),
            // AWS access key id
            Regex::new(r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b").unwrap(),
        ],
    })
}

/// Replace every known secret pattern in `input` with `[REDACTED]`.
pub fn redact(input: &str) -> String {
    let mut out = input.to_owned();
    for re in &patterns().set {
        out = re.replace_all(&out, PLACEHOLDER).into_owned();
    }
    out
}

/// `io::Write` wrapper that redacts each written chunk. Wraps the subscriber's
/// sink so redaction is layer-agnostic.
pub struct RedactingWriter<W> {
    inner: W,
}

impl<W: Write> RedactingWriter<W> {
    pub fn new(inner: W) -> Self {
        RedactingWriter { inner }
    }
}

impl<W: Write> Write for RedactingWriter<W> {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        let text = String::from_utf8_lossy(buf);
        let scrubbed = redact(&text);
        self.inner.write_all(scrubbed.as_bytes())?;
        // Report the original length consumed — callers expect `buf.len()`.
        Ok(buf.len())
    }
    fn flush(&mut self) -> io::Result<()> {
        self.inner.flush()
    }
}

#[cfg(test)]
mod tests {
    use super::redact;

    #[test]
    fn scrubs_openai_key() {
        let s = redact("token=sk-abcDEF0123456789ghijkl tail");
        assert!(!s.contains("sk-abcDEF0123456789"), "got: {s}");
        assert!(s.contains("[REDACTED]"));
        assert!(s.contains("tail"));
    }

    #[test]
    fn scrubs_github_pat() {
        let s = redact("ghp_0123456789ABCDEFabcdef0123456789AB");
        assert!(!s.contains("ghp_0123456789"), "got: {s}");
        assert!(s.contains("[REDACTED]"));
    }

    #[test]
    fn scrubs_jwt() {
        let jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.abc-DEF_123";
        let s = redact(&format!("auth {jwt}"));
        assert!(!s.contains(jwt), "got: {s}");
        assert!(s.contains("[REDACTED]"));
    }

    #[test]
    fn scrubs_aws_key() {
        let s = redact("key AKIAIOSFODNN7EXAMPLE done");
        assert!(!s.contains("AKIAIOSFODNN7EXAMPLE"), "got: {s}");
        assert!(s.contains("[REDACTED]"));
        assert!(s.contains("done"));
    }

    #[test]
    fn leaves_clean_text_untouched() {
        assert_eq!(redact("just a normal log line"), "just a normal log line");
    }
}
