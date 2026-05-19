//! Secret redaction for log output (SEC-FR-19). Every byte written by the
//! tracing subscriber passes through [`redact`] before hitting the sink, so a
//! secret accidentally placed in a span field / message is scrubbed regardless
//! of which layer emitted it.

use regex::Regex;
use std::io::{self, Write};
use std::sync::OnceLock;

const PLACEHOLDER: &str = "[REDACTED]";

fn patterns() -> &'static Vec<Regex> {
    static P: OnceLock<Vec<Regex>> = OnceLock::new();
    P.get_or_init(|| {
        vec![
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
            // Generic password/secret/passwd/pwd assignments
            Regex::new(r"(?i)(password|passwd|pwd|secret)\s*[:=]\s*\S+").unwrap(),
            // AWS secret access key heuristic (40-char value following aws secret/key context)
            Regex::new(r"(?i)aws.{0,20}(?:secret|key).{0,20}[:=]\s*[A-Za-z0-9/+=]{40}").unwrap(),
            // Bearer tokens
            Regex::new(r"Bearer\s+[A-Za-z0-9._\-]+").unwrap(),
            // Google API key (AIza prefix)
            Regex::new(r"AIza[0-9A-Za-z_\-]{35}").unwrap(),
            // PEM private key blocks
            Regex::new(r"-----BEGIN[^-]+PRIVATE KEY-----").unwrap(),
        ]
    })
}

/// Replace every known secret pattern in `input` with `[REDACTED]`.
pub fn redact(input: &str) -> String {
    let mut out = input.to_owned();
    for re in patterns() {
        out = re.replace_all(&out, PLACEHOLDER).into_owned();
    }
    out
}

/// `io::Write` wrapper that redacts log output line-by-line to avoid
/// chunk-boundary bypass (SEC-FR-19). Complete lines (terminated by `\n`) are
/// redacted and forwarded immediately; any trailing partial line is held in an
/// internal buffer until the next write or an explicit flush()/Drop.
pub struct RedactingWriter<W: Write> {
    inner: W,
    /// Bytes not yet terminated by a newline.
    pending: Vec<u8>,
}

impl<W: Write> RedactingWriter<W> {
    pub fn new(inner: W) -> Self {
        RedactingWriter {
            inner,
            pending: Vec::new(),
        }
    }

    /// Emit all complete lines currently in `pending + extra`, holding back any
    /// trailing partial line. Returns an error if the inner writer fails.
    fn flush_lines(&mut self, extra: &[u8]) -> io::Result<()> {
        // Combine buffered bytes with the new chunk.
        let combined: Vec<u8> = self
            .pending
            .iter()
            .copied()
            .chain(extra.iter().copied())
            .collect();
        self.pending.clear();

        // Split on newlines, forwarding each complete line.
        let mut start = 0;
        for i in 0..combined.len() {
            if combined[i] == b'\n' {
                let line = &combined[start..=i];
                let text = String::from_utf8_lossy(line);
                let scrubbed = redact(&text);
                self.inner.write_all(scrubbed.as_bytes())?;
                start = i + 1;
            }
        }
        // Keep the trailing partial line buffered.
        self.pending.extend_from_slice(&combined[start..]);
        Ok(())
    }

    /// Flush the pending partial-line buffer to the inner writer.
    fn flush_pending(&mut self) -> io::Result<()> {
        if self.pending.is_empty() {
            return Ok(());
        }
        let text = String::from_utf8_lossy(&self.pending);
        let scrubbed = redact(&text);
        self.inner.write_all(scrubbed.as_bytes())?;
        self.pending.clear();
        Ok(())
    }
}

impl<W: Write> Write for RedactingWriter<W> {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        self.flush_lines(buf)?;
        // Always report that all bytes were consumed so callers don't retry.
        Ok(buf.len())
    }

    fn flush(&mut self) -> io::Result<()> {
        self.flush_pending()?;
        self.inner.flush()
    }
}

impl<W: Write> Drop for RedactingWriter<W> {
    fn drop(&mut self) {
        // Best-effort: ignore errors on drop (no panic-in-drop).
        let _ = self.flush_pending();
    }
}

#[cfg(test)]
mod tests {
    use super::{RedactingWriter, redact};
    use std::io::Write;

    // ── existing pattern tests ────────────────────────────────────────────────

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

    // ── new pattern tests (security-engineer-2) ──────────────────────────────

    #[test]
    fn scrubs_password_assignment() {
        let s = redact("config: password=s3cr3tV@lue end");
        assert!(!s.contains("s3cr3tV@lue"), "got: {s}");
        assert!(s.contains("[REDACTED]"));
    }

    #[test]
    fn scrubs_secret_colon_assignment() {
        let s = redact("secret: mysupersecret123");
        assert!(!s.contains("mysupersecret123"), "got: {s}");
        assert!(s.contains("[REDACTED]"));
    }

    #[test]
    fn scrubs_aws_secret_access_key() {
        let key = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY";
        let s = redact(&format!("aws_secret_access_key={key}"));
        assert!(!s.contains(key), "got: {s}");
        assert!(s.contains("[REDACTED]"));
    }

    #[test]
    fn scrubs_bearer_token() {
        let s = redact("Authorization: Bearer eyABC.def.ghi");
        assert!(!s.contains("eyABC.def.ghi"), "got: {s}");
        assert!(s.contains("[REDACTED]"));
    }

    #[test]
    fn scrubs_google_api_key() {
        let key = "AIzaSyD-9tSrke72PouQMnMX-a7eZSW0jkFMBWY";
        let s = redact(&format!("api_key={key}"));
        assert!(!s.contains(key), "got: {s}");
        assert!(s.contains("[REDACTED]"));
    }

    #[test]
    fn scrubs_pem_private_key_header() {
        let s = redact("-----BEGIN RSA PRIVATE KEY-----");
        assert!(!s.contains("BEGIN RSA PRIVATE KEY"), "got: {s}");
        assert!(s.contains("[REDACTED]"));
    }

    // ── chunk-boundary test (security-engineer-1) ────────────────────────────

    #[test]
    fn chunk_boundary_secret_is_redacted() {
        // Split a GitHub PAT across two write() calls at an arbitrary boundary.
        let pat = "ghp_0123456789ABCDEFabcdef0123456789AB";
        let line = format!("token={pat}\n");
        let mid = line.len() / 2;
        let (first, second) = line.split_at(mid);

        let mut buf: Vec<u8> = Vec::new();
        {
            let mut writer = RedactingWriter::new(&mut buf);
            writer.write_all(first.as_bytes()).unwrap();
            writer.write_all(second.as_bytes()).unwrap();
            writer.flush().unwrap();
        } // writer dropped here, borrow of buf released

        let output = String::from_utf8(buf).unwrap();
        assert!(
            !output.contains(pat),
            "secret leaked at chunk boundary: {output}"
        );
        assert!(
            output.contains("[REDACTED]"),
            "expected placeholder: {output}"
        );
    }
}
