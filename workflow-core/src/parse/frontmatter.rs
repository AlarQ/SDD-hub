/// Extract YAML frontmatter from markdown content.
/// Returns the text between the first pair of `---` delimiters, or None.
pub fn extract_frontmatter(content: &str) -> Option<String> {
    let normalized = content.replace("\r\n", "\n");
    let trimmed = normalized.trim_start();
    let rest = trimmed.strip_prefix("---")?;
    let after_first = rest.strip_prefix('\n').unwrap_or(rest);
    if after_first.starts_with("---") {
        return Some(String::new());
    }
    let end = after_first.find("\n---")?;
    Some(after_first[..end].to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn extracts_frontmatter() {
        let input = "---\nid: \"001\"\nname: test\n---\n# Body\nSome content";
        let fm = extract_frontmatter(input).unwrap();
        assert!(fm.contains("id: \"001\""));
        assert!(fm.contains("name: test"));
        assert!(!fm.contains("# Body"));
    }

    #[test]
    fn returns_none_without_delimiters() {
        assert!(extract_frontmatter("no frontmatter here").is_none());
    }

    #[test]
    fn returns_none_with_single_delimiter() {
        assert!(extract_frontmatter("---\nid: 1\nno closing").is_none());
    }

    #[test]
    fn handles_empty_frontmatter() {
        let input = "---\n---\nbody";
        let fm = extract_frontmatter(input).unwrap();
        assert!(fm.is_empty());
    }

    #[test]
    fn handles_crlf_line_endings() {
        let input = "---\r\nid: \"001\"\r\nname: test\r\n---\r\n# Body";
        let fm = extract_frontmatter(input).unwrap();
        assert!(fm.contains("id: \"001\""));
        assert!(fm.contains("name: test"));
    }
}
