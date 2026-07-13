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

#[derive(Clone, Copy, PartialEq)]
pub struct Pos {
    pub line: i32,
    pub symbol: i32,
}

pub fn meta<'a>(name: &'a str, code: &'a str) -> Meta<'a> {
    Meta {
        name,
        lines: code.lines().collect(),
    }
}
