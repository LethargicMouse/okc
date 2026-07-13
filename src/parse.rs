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

// tested
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

    // tested
    fn ast(&mut self) -> Res<Ast<'a>> {
        let funs = self.many(Self::fun);
        self.expect(Eof)?;
        Ok(Ast { funs })
    }

    // tested
    fn many<T>(&mut self, parse: fn(&mut Self) -> Res<T>) -> Vec<T> {
        let mut res = Vec::new();
        while let Some(item) = self.maybe(parse) {
            res.push(item);
        }
        res
    }

    // tested
    fn maybe<T>(&mut self, parse: fn(&mut Self) -> Res<T>) -> Option<T> {
        let before = self.cursor;
        let res = parse(self).ok();
        if res.is_none() {
            self.cursor = before;
        }
        res
    }

    // tested
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

    // tested
    fn statement(&mut self) -> Res<Statement> {
        self.expect(Name("return"))?;
        let expr = self.expr()?;
        self.expect(Semicolon)?;
        Ok(Statement::Return(expr))
    }

    // test
    fn expr(&mut self) -> Res<Expr> {
        let int = self.int()?;
        Ok(Expr::Int(int))
    }

    // dont wanna test im tired
    fn name(&mut self) -> Res<&'a str> {
        if let Name(name) = self.tokens[self.cursor].lexeme {
            self.cursor += 1;
            Ok(name)
        } else {
            self.fail("name");
            Err(())
        }
    }

    // dont wanna test im tired
    fn int(&mut self) -> Res<i64> {
        if let Int(int) = self.tokens[self.cursor].lexeme {
            self.cursor += 1;
            Ok(int)
        } else {
            self.fail("int");
            Err(())
        }
    }

    // tested
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

    // dont wanna test im tired
    fn expect(&mut self, lexeme: Lexeme<'a>) -> Res<()> {
        if self.tokens[self.cursor].lexeme == lexeme {
            self.cursor += 1;
            Ok(())
        } else {
            self.fail(lexeme.describe());
            Err(())
        }
    }

    // tested
    fn error(self) -> ParseError<'a> {
        ParseError {
            location: self.tokens[self.err_cursor].location,
            msgs: self.err_msgs,
        }
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        compile::read_file,
        lex::{
            lex,
            tests::{FAKE_META, pos},
        },
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
                body: vec![Statement::Return(Expr::Int(123))],
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

    fn fake_tokens<'a>(lexemes: &[Lexeme<'a>]) -> Vec<Token<'a>> {
        lexemes
            .iter()
            .enumerate()
            .map(|(i, &lexeme)| Token {
                lexeme,
                location: Location {
                    start: pos(1, i as i32),
                    end: pos(1, i as i32 + 1),
                    meta: FAKE_META,
                },
            })
            .collect()
    }

    #[test]
    fn test_many() {
        let tokens = fake_tokens(&[Int(1), Int(2), Int(3), Eof]);
        let mut parser = Parser::new(tokens);
        let expected = vec![1, 2, 3];
        let found = parser.many(Parser::int);
        assert_eq!(expected, found);
        assert_eq!(3, parser.cursor);
    }

    #[test]
    fn test_many_none() {
        let tokens = fake_tokens(&[Int(1), ParL, Int(2), Int(3), Eof]);
        let mut parser = Parser::new(tokens);
        parser.cursor = 1;
        let expected: Vec<i64> = Vec::new();
        let found = parser.many(Parser::int);
        assert_eq!(expected, found);
        assert_eq!(1, parser.cursor);
    }

    #[test]
    fn test_maybe() {
        let tokens = fake_tokens(&[ParL, ParL, Int(2)]);
        let mut parser = Parser::new(tokens);
        parser.cursor = 1;
        let expected = Some(2);
        let found = parser.maybe(|p| {
            p.expect(ParL)?;
            p.int()
        });
        assert_eq!(expected, found);
        assert_eq!(3, parser.cursor);
    }

    #[test]
    fn test_maybe_none() {
        let tokens = fake_tokens(&[ParL, ParL, Int(2)]);
        let mut parser = Parser::new(tokens);
        let expected = None;
        let found = parser.maybe(|p| {
            p.expect(ParL)?;
            p.int()
        });
        assert_eq!(expected, found);
        assert_eq!(0, parser.cursor);
    }

    #[test]
    fn test_fun_empty() {
        let tokens = fake_tokens(&[
            Name("fn"),
            Name("hello"),
            ParL,
            ParR,
            Name("i32"),
            CurL,
            CurR,
        ]);
        let mut parser = Parser::new(tokens);
        let expected = Ok(Fun {
            name: "hello",
            body: vec![],
        });
        let found = parser.fun();
        assert_eq!(expected, found);
        assert_eq!(7, parser.cursor)
    }

    #[test]
    fn test_fun_wrong() {
        let tokens = fake_tokens(&[
            Name("fn"),
            Name("hello"),
            ParR,
            ParL,
            Name("i32"),
            CurL,
            CurR,
        ]);
        let mut parser = Parser::new(tokens);
        let expected = Err(());
        let found = parser.fun();
        assert_eq!(expected, found);
        assert_eq!(2, parser.cursor)
    }

    #[test]
    fn test_statement() {
        let tokens = fake_tokens(&[Name("return"), Int(123), Semicolon]);
        let mut parser = Parser::new(tokens);
        let expected = Ok(Statement::Return(Expr::Int(123)));
        let found = parser.statement();
        assert_eq!(expected, found);
        assert_eq!(3, parser.cursor)
    }

    #[test]
    fn test_statement_wrong() {
        let tokens = fake_tokens(&[Name("return"), Name("return"), Semicolon]);
        let mut parser = Parser::new(tokens);
        let expected = Err(());
        let found = parser.statement();
        assert_eq!(expected, found);
        assert_eq!(1, parser.cursor)
    }

    #[test]
    fn test_expr() {
        let tokens = fake_tokens(&[Int(123)]);
        let mut parser = Parser::new(tokens);
        let expected = Ok(Expr::Int(123));
        let found = parser.expr();
        assert_eq!(expected, found);
        assert_eq!(1, parser.cursor)
    }

    #[test]
    fn test_expr_wrong() {
        let tokens = fake_tokens(&[Semicolon]);
        let mut parser = Parser::new(tokens);
        let expected = Err(());
        let found = parser.expr();
        assert_eq!(expected, found);
        assert_eq!(0, parser.cursor)
    }

    #[test]
    fn test_fail() {
        let tokens = fake_tokens(&[ParL, ParL, ParL, ParL]);
        let mut parser = Parser::new(tokens);
        parser.cursor = 1;
        parser.err_cursor = 1;
        parser.err_msgs.push("elloh");
        parser.fail("hello");
        assert_eq!(1, parser.err_cursor);
        assert_eq!(vec!["elloh", "hello"], parser.err_msgs)
    }

    #[test]
    fn test_fail_before() {
        let tokens = fake_tokens(&[ParL, ParL, ParL, ParL]);
        let mut parser = Parser::new(tokens);
        parser.cursor = 1;
        parser.err_cursor = 2;
        parser.err_msgs.push("elloh");
        parser.fail("hello");
        assert_eq!(2, parser.err_cursor);
        assert_eq!(vec!["elloh"], parser.err_msgs)
    }

    #[test]
    fn test_fail_after() {
        let tokens = fake_tokens(&[ParL, ParL, ParL, ParL]);
        let mut parser = Parser::new(tokens);
        parser.cursor = 2;
        parser.err_cursor = 1;
        parser.err_msgs.push("elloh");
        parser.fail("hello");
        assert_eq!(2, parser.err_cursor);
        assert_eq!(vec!["hello"], parser.err_msgs)
    }
}
