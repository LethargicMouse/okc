use crate::{
    RED, RESET,
    source::{Location, Meta, Pos},
};
use Lexeme::*;
use std::process::exit;

pub fn lex<'a>(code: &'a str, meta: &'a Meta<'a>) -> Vec<Token<'a>> {
    let mut res = Vec::new();
    let mut lexer = Lexer::new(code, meta);
    lexer.populate(&mut res);
    res
}

fn make_poses(code: &str) -> Vec<Pos> {
    code.chars()
        .chain("  ".chars())
        .scan(Pos { line: 1, symbol: 1 }, |p, c| {
            let res = *p;
            if c == '\n' {
                p.line += 1;
                p.symbol = 1;
            } else {
                p.symbol += 1;
            }
            Some(res)
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
    RawStr(&'a str),
    ParL,
    ParR,
    CurL,
    CurR,
    Semicolon,
    Colon,
    Star,
    Eof,
    Error,
}

impl<'a> Lexeme<'a> {
    pub fn describe(&self) -> &'a str {
        // FIXME some of those should not be here, gotta fix the parser msgs
        match self {
            Name("fn") => "`fn`",
            Name("return") => "`return`",
            Name("extern") => "`extern`",
            Name("i32") => "`i32`",
            ParL => "`(`",
            ParR => "`)`",
            CurL => "`{`",
            CurR => "`}`",
            Semicolon => "`;`",
            Eof => "<eof>",
            Star => "`*`",
            lexeme => unreachable!("{lexeme:?}"),
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
                .or_else(|| self.try_raw_str())
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
            (":", Colon),
            ("*", Star),
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

    fn try_raw_str(&mut self) -> Option<Token<'a>> {
        if !self.code[self.cursor..].starts_with("r\"") {
            return None;
        }
        self.cursor += 2;
        let res = self.take_while(|c| *c != '\"');
        self.cursor -= 2;
        if res.len() == self.code.len() - self.cursor - 2 {
            eprintln!(
                "{RED}error:{RESET} unclosed string delimeter in {}",
                self.location(1)
            );
            exit(1);
        }
        Some(self.token(Lexeme::RawStr(res), res.len() + 3))
    }

    fn next(&self) -> char {
        self.code[self.cursor..].chars().next().unwrap()
    }
}

#[cfg(test)]
mod tests {
    use crate::{
        compile::read_file,
        lex::{Lexeme, lex},
        source::meta,
    };

    fn test_lex(path: &str) {
        let code = read_file(path);
        let meta = meta(path, &code);
        let tokens = lex(&code, &meta);
        if tokens.iter().any(|t| t.lexeme == Lexeme::Error) {
            panic!(
                "lex failed: {:?}",
                tokens.iter().map(|t| t.lexeme).collect::<Vec<_>>()
            );
        }
    }

    #[test]
    fn test_lex_empty() {
        test_lex("examples/empty.ok");
    }

    #[test]
    fn test_lex_simple_call() {
        test_lex("examples/simple_call.ok");
    }
}
