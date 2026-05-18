use std::fmt;

#[derive(Debug)]
pub enum ParseWarning {
    MalformedLine {
        source: String,
        line: usize,
        cause: String,
    },
    FileReadError {
        path: String,
        cause: String,
    },
    Truncated {
        source: String,
        max: usize,
    },
}

impl fmt::Display for ParseWarning {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::MalformedLine {
                source,
                line,
                cause,
            } => write!(f, "{source}:{line}: {cause}"),
            Self::FileReadError { path, cause } => write!(f, "{path}: {cause}"),
            Self::Truncated { source, max } => write!(f, "{source}: truncated at {max} events"),
        }
    }
}
