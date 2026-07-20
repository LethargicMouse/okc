use std::fmt::Display;

const RED: &str = "\x1b[0;31m";
const RESET: &str = "\x1b[0m";

pub struct LogError;

impl Display for LogError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{RED}error:{RESET} ")
    }
}
