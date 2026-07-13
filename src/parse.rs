use std::{cmp::Ordering, fmt::Display};

use crate::{
    RED, RESET,
    lex::{
        Lexeme::{self, *},
        Token,
    },
    source::Location,
};

#[derive(Debug, PartialEq)]
pub struct Ast<'a> {
    pub funs: Vec<Fun<'a>>,
}

#[derive(Debug, PartialEq)]
pub struct Fun<'a> {
    pub name: &'a str,
    pub body: Vec<Statement>,
}

#[derive(Debug, PartialEq)]
pub enum Statement {
    Return(Expr),
}

#[derive(Debug, PartialEq)]
pub enum Expr {
    Int(i64),
}

pub fn parse<'a>(tokens: Vec<Token<'a>>) -> Result<Ast<'a>, ParseError<'a>> {
    let mut parser = Parser::new(tokens);
    parser.ast().map_err(|_| parser.error())
}

#[derive(Default)]
struct Parser<'a> {
    tokens: Vec<Token<'a>>,
    cursor: usize,
    err_cursor: usize,
    err_msgs: Vec<&'a str>,
}

type Res<T> = Result<T, ()>;

impl<'a> Parser<'a> {
    fn new(tokens: Vec<Token<'a>>) -> Self {
        Self {
            tokens,
            ..Default::default()
        }
    }

    fn ast(&mut self) -> Res<Ast<'a>> {
        let funs = self.many(Self::fun);
        self.expect(Eof)?;
        Ok(Ast { funs })
    }

    fn many<T>(&mut self, parse: fn(&mut Self) -> Res<T>) -> Vec<T> {
        let mut res = Vec::new();
        while let Some(item) = self.maybe(parse) {
            res.push(item);
        }
        res
    }

    fn maybe<T>(&mut self, parse: fn(&mut Self) -> Res<T>) -> Option<T> {
        let before = self.cursor;
        let res = parse(self).ok();
        if res.is_none() {
            self.cursor = before;
        }
        res
    }

    fn fun(&mut self) -> Res<Fun<'a>> {
        self.expect(Name("fn"))?;
        let name = self.name()?;
        self.expect(ParL)?;
        self.expect(ParR)?;
        self.expect(Name("i32"))?;
        self.expect(CurL)?;
        let body = self.many(Self::statement);
        self.expect(CurR)?;
        Ok(Fun { name, body })
    }

    fn statement(&mut self) -> Res<Statement> {
        self.expect(Name("return"))?;
        let expr = self.expr()?;
        self.expect(Semicolon)?;
        Ok(Statement::Return(expr))
    }

    fn expr(&mut self) -> Res<Expr> {
        let int = self.int()?;
        Ok(Expr::Int(int))
    }

    fn name(&mut self) -> Res<&'a str> {
        if let Name(name) = self.tokens[self.cursor].lexeme {
            self.cursor += 1;
            Ok(name)
        } else {
            self.fail("name");
            Err(())
        }
    }

    fn int(&mut self) -> Res<i64> {
        if let Int(int) = self.tokens[self.cursor].lexeme {
            self.cursor += 1;
            Ok(int)
        } else {
            self.fail("int");
            Err(())
        }
    }

    fn fail(&mut self, msg: &'a str) {
        match self.cursor.cmp(&self.err_cursor) {
            Ordering::Less => {}
            Ordering::Equal => {
                self.err_msgs.push(msg);
            }
            Ordering::Greater => {
                self.err_cursor = self.cursor;
                self.err_msgs.clear();
                self.err_msgs.push(msg);
            }
        }
    }

    fn expect(&mut self, lexeme: Lexeme<'a>) -> Res<()> {
        if self.tokens[self.cursor].lexeme == lexeme {
            self.cursor += 1;
            Ok(())
        } else {
            self.fail(lexeme.describe());
            Err(())
        }
    }

    fn error(self) -> ParseError<'a> {
        ParseError {
            location: self.tokens[self.err_cursor].location,
            msgs: self.err_msgs,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        lex::lex,
        read_file,
        source::{Location, Pos, meta},
    };

    #[test]
    fn parse_empty() {
        let path = "resources/empty.ok";
        let code = read_file(path);
        let meta = meta(path, &code);
        let tokens = lex(&code, &meta);
        let ast = parse(tokens);
        let empty_ast = Ok(Ast {
            funs: vec![Fun {
                name: "main",
                body: vec![Statement::Return(Expr::Int(0))],
            }],
        });
        assert_eq!(ast, empty_ast);
    }

    #[test]
    fn parse_two_funs() {
        let path = "resources/two_funs.ok";
        let code = read_file(path);
        let meta = meta(path, &code);
        let tokens = lex(&code, &meta);
        let expected = Ok(Ast {
            funs: vec![
                Fun {
                    name: "fun_1",
                    body: vec![Statement::Return(Expr::Int(123))],
                },
                Fun {
                    name: "__fun_n2_",
                    body: vec![
                        Statement::Return(Expr::Int(321)),
                        Statement::Return(Expr::Int(444)),
                    ],
                },
            ],
        });
        let found = parse(tokens);
        assert_eq!(expected, found)
    }

    #[test]
    fn parse_fun_wrong_missing() {
        let path = "resources/fun_wrong_missing.ok";
        let code = read_file(path);
        let meta = meta(path, &code);
        let tokens = lex(&code, &meta);
        let expected = Err(ParseError {
            location: Location {
                start: Pos { line: 2, symbol: 3 },
                end: Pos { line: 2, symbol: 9 },
                meta: &meta,
            },
            msgs: vec!["`{`"],
        });
        let found = parse(tokens);
        assert_eq!(expected, found)
    }

    #[test]
    fn parse_fun_wrong_extra() {
        let path = "resources/fun_wrong_extra.ok";
        let code = read_file(path);
        let meta = meta(path, &code);
        let tokens = lex(&code, &meta);
        let expected = Err(ParseError {
            location: Location {
                start: Pos {
                    line: 1,
                    symbol: 10,
                },
                end: Pos {
                    line: 1,
                    symbol: 11,
                },
                meta: &meta,
            },
            msgs: vec!["`i32`"],
        });
        let found = parse(tokens);
        assert_eq!(expected, found)
    }
}

#[derive(Debug, PartialEq)]
pub struct ParseError<'a> {
    location: Location<'a>,
    msgs: Vec<&'a str>,
}

impl Display for ParseError<'_> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "{RED}error:{RESET} failed to parse {}\n  expected:",
            self.location
        )?;
        for msg in &self.msgs {
            write!(f, "\n    {msg}")?;
        }
        Ok(())
    }
}
