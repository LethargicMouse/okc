use Lexeme::*;

use crate::source::{Location, Meta, Pos};

pub fn lex<'a>(code: &'a str, meta: &'a Meta<'a>) -> Vec<Token<'a>> {
    let mut res = Vec::new();
    let mut lexer = Lexer::new(code, meta);
    lexer.populate(&mut res);
    res
}

fn make_poses(code: &str) -> Vec<Pos> {
    code.chars()
        .chain("  ".chars())
        .scan(Pos { line: 1, symbol: 0 }, |p, c| {
            if c == '\n' {
                p.line += 1;
                p.symbol = 0;
            } else {
                p.symbol += 1;
            }
            Some(*p)
        })
        .collect()
}

#[derive(Debug, PartialEq)]
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
            Name("fn") => "`fn`",
            // FIXME should not be here, gotta fix the parser msgs
            Name("return") => "`return`",
            Name("i32") => "`i32`",
            ParL => "`(`",
            ParR => "`)`",
            CurL => "`{`",
            CurR => "`}`",
            Semicolon => "`;`",
            Eof => "<eof>",
            _ => unreachable!(),
        }
    }
}

struct Lexer<'a> {
    code: &'a str,
    poses: Vec<Pos>,
    cursor: usize,
    meta: &'a Meta<'a>,
}

impl<'a> Lexer<'a> {
    fn new(code: &'a str, meta: &'a Meta<'a>) -> Self {
        Self {
            code,
            poses: make_poses(code),
            meta,
            cursor: 0,
        }
    }

    fn token(&mut self, lexeme: Lexeme<'a>, len: usize) -> Token<'a> {
        let location = self.location(len);
        self.cursor += len;
        Token { lexeme, location }
    }

    fn skip_spaces(&mut self) {
        self.cursor += self.take_while(|c| c.is_whitespace()).len();
    }

    fn populate(&mut self, res: &mut Vec<Token<'a>>) {
        'main: loop {
            let old = self.cursor;
            self.skip_spaces();
            if self.cursor == self.code.len() {
                self.cursor = old;
                res.push(self.token(Eof, 1));
                break;
            }
            if let Some(token) = self
                .try_list()
                .or_else(|| self.try_name())
                .or_else(|| self.try_int())
            {
                res.push(token);
                continue 'main;
            }
            res.push(self.token(Error, 1));
            break;
        }
    }

    fn take_while(&self, predicate: fn(&char) -> bool) -> &'a str {
        &self.code[self.cursor
            ..self.cursor
                + self.code[self.cursor..]
                    .chars()
                    .take_while(predicate)
                    .count()]
    }

    fn location(&self, len: usize) -> Location<'a> {
        Location {
            start: self.poses[self.cursor],
            end: self.poses[self.cursor + len],
            meta: self.meta,
        }
    }

    fn try_list(&mut self) -> Option<Token<'a>> {
        let lex_list = [
            ("(", ParL),
            (")", ParR),
            ("{", CurL),
            ("}", CurR),
            (";", Semicolon),
        ];
        for (pattern, lexeme) in lex_list {
            if self.code[self.cursor..].starts_with(pattern) {
                return Some(self.token(lexeme, pattern.len()));
            }
        }
        None
    }

    fn try_name(&mut self) -> Option<Token<'a>> {
        let c = self.next();
        if c.is_alphabetic() || c == '_' {
            let name = self.take_while(|c| c.is_alphanumeric() || *c == '_');
            Some(self.token(Name(name), name.len()))
        } else {
            None
        }
    }

    fn try_int(&mut self) -> Option<Token<'a>> {
        let c = self.next();
        if c.is_ascii_digit() {
            let int = self.take_while(|c| c.is_ascii_digit());
            Some(self.token(Int(int.parse().unwrap()), int.len()))
        } else {
            None
        }
    }

    fn next(&self) -> char {
        self.code[self.cursor..].chars().next().unwrap()
    }
}
