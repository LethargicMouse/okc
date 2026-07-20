use crate::{
    display::LogError,
    source::{Location, Meta, Pos, Source},
};
use Lexeme::*;
use std::process::exit;

pub fn lex<'a>(source: &'a Source<'a>) -> Vec<Token<'a>> {
    let mut res = Vec::new();
    let mut lexer = Lexer::new(source);
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
    Int(u64),
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
    Comma,
    Equal,
    Plus,
}

impl<'a> Lexeme<'a> {
    pub fn describe(&self) -> &'a str {
        // FIXME some of those should not be here, gotta fix the parser msgs
        match self {
            Name("fn") => "`fn`",
            Name("return") => "`return`",
            Name("extern") => "`extern`",
            Name("let") => "`let`",
            Name("i32") => "`i32`",
            Plus => "`+`",
            Equal => "`=`",
            Comma => "`,`",
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
    poses: Vec<Pos>,
    cursor: usize,
    source: &'a Source<'a>,
}

impl<'a> Lexer<'a> {
    fn new(source: &'a Source<'a>) -> Self {
        Self {
            poses: make_poses(source.code),
            cursor: 0,
            source,
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
            if self.cursor == self.source.code.len() {
                self.cursor = old;
                res.push(self.token(Eof, 1));
                break;
            }
            if let Some(token) = self
                .try_list()
                .or_else(|| self.try_raw_str())
                .or_else(|| self.try_str())
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
        &self.source.code[self.cursor
            ..self.cursor
                + self.source.code[self.cursor..]
                    .chars()
                    .take_while(predicate)
                    .count()]
    }

    fn location(&self, len: usize) -> Location<'a> {
        Location {
            start: self.poses[self.cursor],
            end: self.poses[self.cursor + len],
            meta: &self.source.meta,
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
            (",", Comma),
            ("=", Equal),
            ("+", Plus),
        ];
        for (pattern, lexeme) in lex_list {
            if self.source.code[self.cursor..].starts_with(pattern) {
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

    fn try_str_with(&mut self, prefix: &str) -> Option<Token<'a>> {
        if !self.source.code[self.cursor..].starts_with(prefix) {
            return None;
        }
        self.cursor += prefix.len();
        let res = self.take_while(|c| *c != '\"');
        self.cursor -= prefix.len();
        if res.len() == self.source.code.len() - self.cursor - prefix.len() {
            eprintln!(
                "{LogError} unclosed string delimeter in {}",
                self.location(1)
            );
            exit(1);
        }
        Some(self.token(Lexeme::RawStr(res), res.len() + prefix.len() + 1))
    }

    fn try_raw_str(&mut self) -> Option<Token<'a>> {
        self.try_str_with("r\"")
    }

    fn try_str(&mut self) -> Option<Token<'a>> {
        self.try_str_with("\"")
    }

    fn next(&self) -> char {
        self.source.code[self.cursor..].chars().next().unwrap()
    }
}

#[cfg(test)]
mod tests {
    use crate::{
        compile::read_file,
        lex::{Lexeme, lex},
        source::Source,
    };

    fn test_lex(name: &str) {
        let path = format!("examples/{name}.ok");
        let code = read_file(&path);
        let source = Source::new(&path, &code);
        let tokens = lex(&source);
        if tokens.iter().any(|t| t.lexeme == Lexeme::Error) {
            panic!(
                "lex failed: {:?}",
                tokens.iter().map(|t| t.lexeme).collect::<Vec<_>>()
            );
        }
    }

    #[test]
    fn test_lex_empty() {
        test_lex("empty");
    }

    #[test]
    fn test_lex_simple_call() {
        test_lex("simple_call");
    }

    #[test]
    fn test_lex_simple_call_2() {
        test_lex("simple_call_2")
    }

    #[test]
    fn test_lex_var() {
        test_lex("var")
    }

    #[test]
    fn test_lex_var_assign() {
        test_lex("var_assign");
    }

    #[test]
    fn test_lex_add() {
        test_lex("add")
    }
}
