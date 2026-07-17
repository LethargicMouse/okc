use std::fmt::{Debug, Display};

use crate::source::{Location, Pos};

impl Debug for Location<'_> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "`{}`: [{} - {})", self.meta.name, self.start, self.end)
    }
}

impl Display for Location<'_> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        dbg!(self.start, self.end);
        write!(f, "`{}` at {}:\n     |", self.meta.name, self.start)?;
        write!(f, "{}", Line(self.start.line, &self.meta.lines))?;
        write!(f, "{}", Underline(self.start.symbol, self.end.symbol))
    }
}

struct Line<'a>(i32, &'a [&'a str]);

impl Display for Line<'_> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "\n{:4} | {}", self.0, self.1[self.0 as usize - 1])
    }
}

struct Underline(i32, i32);

impl Display for Underline {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "\n     |")?;
        for _ in 0..self.0 {
            write!(f, " ")?;
        }
        for _ in self.0..self.1 {
            write!(f, "`")?;
        }
        Ok(())
    }
}

impl Display for Pos {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}:{}", self.line, self.symbol)
    }
}

impl Debug for Pos {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{self}")
    }
}
