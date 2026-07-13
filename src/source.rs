use std::fmt::{Debug, Display};

pub struct Meta<'a> {
    pub name: &'a str,
    pub lines: Vec<&'a str>,
}

#[derive(Clone, Copy)]
pub struct Location<'a> {
    pub start: Pos,
    pub end: Pos,
    pub meta: &'a Meta<'a>,
}

impl PartialEq for Location<'_> {
    fn eq(&self, other: &Self) -> bool {
        self.start == other.start && self.end == other.end && self.meta.name == other.meta.name
    }
}

impl Debug for Location<'_> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "`{}`: [{} - {})", self.meta.name, self.start, self.end)
    }
}

impl Display for Location<'_> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "`{}` at {}:\n     |", self.meta.name, self.start)?;
        write!(f, "{}", Line(self.start.line, &self.meta.lines))?;
        Ok(())
    }
}

struct Line<'a>(i32, &'a [&'a str]);

impl Display for Line<'_> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{:4} | {}", self.0, self.1[self.0 as usize - 1])
    }
}

#[derive(Clone, Copy, PartialEq)]
pub struct Pos {
    pub line: i32,
    pub symbol: i32,
}

impl Display for Pos {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}:{}", self.line, self.symbol)
    }
}
