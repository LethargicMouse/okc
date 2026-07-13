use Lexeme::*;

use crate::source::{Location, Meta, Pos};

// tested
pub fn lex<'a>(code: &'a str, meta: &'a Meta<'a>) -> Vec<Token<'a>> {
    let mut res = Vec::new();
    let mut lexer = Lexer::new(code, meta);
    lexer.populate(&mut res);
    res
}

// tested
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
    // tested
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

    // tested
    fn token(&mut self, lexeme: Lexeme<'a>, len: usize) -> Token<'a> {
        let location = self.location(len);
        self.cursor += len;
        Token { lexeme, location }
    }

    // tested
    fn skip_spaces(&mut self) {
        self.cursor += self.take_while(|c| c.is_whitespace()).len();
    }

    // tested
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

    // tested
    fn take_while(&self, predicate: fn(&char) -> bool) -> &'a str {
        &self.code[self.cursor
            ..self.cursor
                + self.code[self.cursor..]
                    .chars()
                    .take_while(predicate)
                    .count()]
    }

    // tested by test_token
    fn location(&self, len: usize) -> Location<'a> {
        Location {
            start: self.poses[self.cursor],
            end: self.poses[self.cursor + len],
            meta: self.meta,
        }
    }

    // tested
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

    // tested
    fn try_name(&mut self) -> Option<Token<'a>> {
        let c = self.next();
        if c.is_alphabetic() || c == '_' {
            let name = self.take_while(|c| c.is_alphanumeric() || *c == '_');
            Some(self.token(Name(name), name.len()))
        } else {
            None
        }
    }

    // tested
    fn try_int(&mut self) -> Option<Token<'a>> {
        let c = self.next();
        if c.is_ascii_digit() {
            let int = self.take_while(|c| c.is_ascii_digit());
            Some(self.token(Int(int.parse().unwrap()), int.len()))
        } else {
            None
        }
    }

    // tested
    fn next(&self) -> char {
        self.code[self.cursor..].chars().next().unwrap()
    }
}

#[cfg(test)]
pub mod tests {
    use crate::{read_file, source::meta};

    use super::*;

    fn mk_lexemes<'a>(code: &'a str, meta: &'a Meta) -> Vec<Lexeme<'a>> {
        lex(code, meta).iter().map(|t| t.lexeme).collect()
    }

    pub const FAKE_META: &Meta = &Meta {
        name: "fake",
        lines: Vec::new(),
    };

    #[test]
    fn lex_empty() {
        let code = include_str!("../resources/empty.ok");
        let tokens = mk_lexemes(code, FAKE_META);
        let empty_ok_lexemes = vec![
            Name("fn"),
            Name("main"),
            ParL,
            ParR,
            Name("i32"),
            CurL,
            Name("return"),
            Int(123),
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

    pub fn pos(line: i32, symbol: i32) -> Pos {
        Pos { line, symbol }
    }

    #[test]
    fn test_make_poses() {
        let code = "hello\n  there\n\n!\n";
        let expected = vec![
            pos(1, 1),
            pos(1, 2),
            pos(1, 3),
            pos(1, 4),
            pos(1, 5),
            pos(2, 0),
            pos(2, 1),
            pos(2, 2),
            pos(2, 3),
            pos(2, 4),
            pos(2, 5),
            pos(2, 6),
            pos(2, 7),
            pos(3, 0),
            pos(4, 0),
            pos(4, 1),
            pos(5, 0),
            pos(5, 1),
            pos(5, 2),
        ];
        let found = make_poses(code);
        assert_eq!(expected, found)
    }

    #[test]
    fn test_describe() {
        assert_eq!(CurL.describe(), "`{`");
        assert_eq!(Name("fn").describe(), "`fn`");
        assert_eq!(Eof.describe(), "<eof>");
    }

    #[test]
    #[should_panic]
    fn test_describe_fail() {
        Int(123).describe();
    }

    #[test]
    fn test_token() {
        let path = "resources/two_funs.ok";
        let code = read_file(path);
        let meta = meta(path, &code);
        let mut lexer = Lexer::new(&code, &meta);
        lexer.cursor = 3;
        let expected = Token {
            lexeme: Name("fun_1"),
            location: Location {
                start: pos(1, 4),
                end: pos(1, 9),
                meta: &meta,
            },
        };
        let found = lexer.token(Name("fun_1"), 5);
        assert_eq!(expected, found)
    }

    #[test]
    fn test_token_eof() {
        let path = "resources/two_funs.ok";
        let code = read_file(path);
        let meta = meta(path, &code);
        let mut lexer = Lexer::new(&code, &meta);
        lexer.cursor = code.len();
        let expecteed = Token {
            lexeme: Eof,
            location: Location {
                start: pos(9, 1),
                end: pos(9, 2),
                meta: &meta,
            },
        };
        let found = lexer.token(Eof, 1);
        assert_eq!(expecteed, found);
    }

    #[test]
    fn test_skip_space() {
        let path = "resources/two_funs.ok";
        let code = read_file(path);
        let meta = meta(path, &code);
        let mut lexer = Lexer::new(&code, &meta);
        lexer.cursor = 16;
        lexer.skip_spaces();
        assert_eq!(19, lexer.cursor);
    }

    #[test]
    fn test_skip_space_to_eof() {
        let path = "resources/two_funs.ok";
        let code = read_file(path);
        let meta = meta(path, &code);
        let mut lexer = Lexer::new(&code, &meta);
        lexer.cursor = code.rfind('}').unwrap() + 1;
        lexer.skip_spaces();
        assert_eq!(code.len(), lexer.cursor);
    }

    #[test]
    fn test_take_while() {
        let path = "resources/two_funs.ok";
        let code = read_file(path);
        let meta = meta(path, &code);
        let lexer = Lexer::new(&code, &meta);
        let expected = "fn fun";
        let found = lexer.take_while(|c| c.is_alphabetic() || c.is_whitespace());
        assert_eq!(expected, found)
    }

    #[test]
    fn test_take_while_all() {
        let path = "resources/empty.ok";
        let code = read_file(path);
        let meta = meta(path, &code);
        let lexer = Lexer::new(&code, &meta);
        let found = lexer.take_while(|_| true);
        assert_eq!(code, found)
    }

    #[test]
    fn test_try_list() {
        let path = "resources/empty.ok";
        let code = read_file(path);
        let meta = meta(path, &code);
        let mut lexer = Lexer::new(&code, &meta);
        lexer.cursor = 8;
        let expected = Some(Token {
            lexeme: ParR,
            location: Location {
                start: pos(1, 9),
                end: pos(1, 10),
                meta: &meta,
            },
        });
        let found = lexer.try_list();
        assert_eq!(expected, found)
    }

    #[test]
    fn test_try_list_wrong() {
        let path = "resources/empty.ok";
        let code = read_file(path);
        let meta = meta(path, &code);
        let mut lexer = Lexer::new(&code, &meta);
        lexer.cursor = 9;
        assert_eq!(None, lexer.try_list());
    }

    #[test]
    fn test_try_name() {
        let path = "resources/empty.ok";
        let code = read_file(path);
        let meta = meta(path, &code);
        let mut lexer = Lexer::new(&code, &meta);
        lexer.cursor = 10;
        let expected = Some(Token {
            lexeme: Name("i32"),
            location: Location {
                start: pos(1, 11),
                end: pos(1, 14),
                meta: &meta,
            },
        });
        let found = lexer.try_name();
        assert_eq!(expected, found)
    }

    #[test]
    fn test_try_name_wrong() {
        let path = "resources/empty.ok";
        let code = read_file(path);
        let meta = meta(path, &code);
        let mut lexer = Lexer::new(&code, &meta);
        lexer.cursor = 11;
        assert_eq!(None, lexer.try_name());
    }

    #[test]
    fn test_try_int() {
        let path = "resources/empty.ok";
        let code = read_file(path);
        let meta = meta(path, &code);
        let mut lexer = Lexer::new(&code, &meta);
        lexer.cursor = 11;
        let expected = Some(Token {
            lexeme: Int(32),
            location: Location {
                start: pos(1, 12),
                end: pos(1, 14),
                meta: &meta,
            },
        });
        let found = lexer.try_int();
        assert_eq!(expected, found)
    }

    #[test]
    fn test_try_int_wrong() {
        let path = "resources/empty.ok";
        let code = read_file(path);
        let meta = meta(path, &code);
        let mut lexer = Lexer::new(&code, &meta);
        lexer.cursor = 10;
        assert_eq!(None, lexer.try_int());
    }

    #[test]
    fn test_next() {
        let path = "resources/empty.ok";
        let code = read_file(path);
        let meta = meta(path, &code);
        let mut lexer = Lexer::new(&code, &meta);
        lexer.cursor = 10;
        assert_eq!('i', lexer.next())
    }

    #[test]
    #[should_panic]
    fn test_next_wrong() {
        let path = "resources/empty.ok";
        let code = read_file(path);
        let meta = meta(path, &code);
        let mut lexer = Lexer::new(&code, &meta);
        lexer.cursor = code.len();
        lexer.next();
    }
}
