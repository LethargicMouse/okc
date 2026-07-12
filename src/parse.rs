use std::{cmp::Ordering, process::exit};

use crate::{
    RED, RESET,
    lex::{
        Lexeme::{self, *},
        Token,
    },
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

pub fn parse(tokens: Vec<Token>) -> Ast {
    let mut parser = Parser::new(tokens);
    parser.ast().unwrap_or_else(|_| parser.die())
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

    fn die(&self) -> ! {
        eprintln!(
            "{RED}error: parser failed: {} {:?}{RESET}",
            self.err_cursor, self.err_msgs
        );
        exit(1)
    }
}
