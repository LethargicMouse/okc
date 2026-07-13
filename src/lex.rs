use std::fmt::{Debug, Display};

use Lexeme::*;

pub fn lex<'a>(code: &'a str, meta: &'a Meta<'a>) -> Vec<Token<'a>> {
    let mut res = Vec::new();
    let poses = make_poses(code);
    let mut lexer = Lexer::new(code, &poses, meta);
    lexer.populate(&mut res);
    res
}

fn make_poses(code: &str) -> Vec<Pos> {
    code.chars()
        .chain(" :6  ".chars())
        .scan(Pos { line: 1, symbol: 0 }, |p, c| {
            *p = p.after(c);
            Some(*p)
        })
        .collect()
}

pub struct Token<'a> {
    pub lexeme: Lexeme<'a>,
    pub location: Location<'a>,
}

#[derive(Debug, PartialEq, Clone, Copy)]
pub enum Lexeme<'a> {
    Name(&'a str),
    Int(i64),
    ParL,
    ParR,
    CurL,
    CurR,
    Semicolon,
    Eof,
    Error,
}
impl<'a> Lexeme<'a> {
    pub fn describe(&self) -> &'a str {
        match self {
            Name(n) => n,
            ParL => "(",
            ParR => ")",
            CurL => "{",
            CurR => "}",
            Semicolon => ";",
            Eof => "<eof>",
            _ => unreachable!(),
        }
    }
}

struct Lexer<'a, 'b> {
    code: &'a str,
    poses: &'b [Pos],
    meta: &'a Meta<'a>,
}

impl<'a, 'b> Lexer<'a, 'b> {
    pub fn new(code: &'a str, poses: &'b [Pos], meta: &'a Meta<'a>) -> Self {
        Self { code, poses, meta }
    }

    fn token(&mut self, lexeme: Lexeme<'a>, len: usize) -> Token<'a> {
        let location = self.location(len);
        if !self.code.is_empty() {
            self.code = &self.code[len..];
        }
        self.poses = &self.poses[len..];
        Token { lexeme, location }
    }

    fn skip_spaces(&mut self) {
        let old_len = self.code.len();
        self.code = self.code.trim_start();
        self.poses = &self.poses[old_len - self.code.len()..];
    }

    fn populate(&mut self, res: &mut Vec<Token<'a>>) {
        let lex_list = [
            ("(", ParL),
            (")", ParR),
            ("{", CurL),
            ("}", CurR),
            (";", Semicolon),
        ];
        'main: loop {
            self.skip_spaces();
            if self.code.is_empty() {
                res.push(self.token(Eof, 1));
                break;
            }
            for (pattern, lexeme) in lex_list {
                if self.code.starts_with(pattern) {
                    res.push(self.token(lexeme, pattern.len()));
                    continue 'main;
                }
            }
            let c = self.code.chars().next().unwrap();
            if c.is_alphabetic() || c == '_' {
                let name = self.take_while(|c| c.is_alphanumeric() || *c == '_');
                res.push(self.token(Name(name), name.len()));
                continue 'main;
            }
            if c.is_ascii_digit() {
                let int = self.take_while(|c| c.is_ascii_digit());
                res.push(self.token(Int(int.parse().unwrap()), int.len()));
                continue 'main;
            }
            res.push(self.token(Error, 1));
            break;
        }
    }

    fn take_while(&self, predicate: fn(&char) -> bool) -> &'a str {
        &self.code[..self.code.chars().take_while(predicate).count()]
    }

    fn location(&self, len: usize) -> Location<'a> {
        Location {
            start: self.poses[0],
            end: self.poses[len],
            meta: self.meta,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::read_file;

    fn mk_lexemes<'a>(code: &'a str, meta: &'a Meta) -> Vec<Lexeme<'a>> {
        lex(code, meta).iter().map(|t| t.lexeme).collect()
    }

    const FAKE_META: &Meta = &Meta {
        name: "fake",
        lines: Vec::new(),
    };

    #[test]
    fn lex_empty() {
        let code = read_file("resources/empty.ok");
        let tokens = mk_lexemes(&code, FAKE_META);
        let empty_ok_lexemes = vec![
            Name("fn"),
            Name("main"),
            ParL,
            ParR,
            Name("i32"),
            CurL,
            Name("return"),
            Int(0),
            Semicolon,
            CurR,
            Eof,
        ];
        assert_eq!(empty_ok_lexemes, tokens)
    }

    #[test]
    fn lex_no_space() {
        let code = "george){(}((123);}";
        let expected = vec![
            Name("george"),
            ParR,
            CurL,
            ParL,
            CurR,
            ParL,
            ParL,
            Int(123),
            ParR,
            Semicolon,
            CurR,
            Eof,
        ];
        let found = mk_lexemes(code, FAKE_META);
        assert_eq!(expected, found)
    }

    #[test]
    fn lex_wrong_midtext() {
        let code = "george){($}((123);}";
        let expected = vec![Name("george"), ParR, CurL, ParL, Error];
        let found = mk_lexemes(code, FAKE_META);
        assert_eq!(expected, found)
    }

    #[test]
    fn lex_spaced() {
        let code = "george is\nthe\tauthor \n\t  \t\n\n\t ;\n   \n";
        let expected = vec![
            Name("george"),
            Name("is"),
            Name("the"),
            Name("author"),
            Semicolon,
            Eof,
        ];
        let found = mk_lexemes(code, FAKE_META);
        assert_eq!(expected, found)
    }
}

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

impl Pos {
    fn after(mut self, c: char) -> Pos {
        if c == '\n' {
            self.line += 1;
            self.symbol = 0;
        } else {
            self.symbol += 1;
        }
        self
    }
}

impl Display for Pos {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}:{}", self.line, self.symbol)
    }
}
