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
    pub ext_funs: Vec<ExtFun<'a>>,
    pub funs: Vec<Fun<'a>>,
}

#[derive(Debug, PartialEq)]
pub struct ExtFun<'a> {
    pub header: Header<'a>,
}

#[derive(Debug, PartialEq)]
pub struct Fun<'a> {
    pub header: Header<'a>,
    pub body: Vec<Statement<'a>>,
}

#[derive(Debug, PartialEq)]
pub struct Header<'a> {
    pub name: &'a str,
    pub args: Vec<(&'a str, Typ<'a>)>,
}

#[derive(Debug, PartialEq)]
pub enum Typ<'a> {
    Prime(Prime),
    Ptr(Box<Typ<'a>>),
    Name(&'a str),
}

impl<'a> From<Prime> for Typ<'a> {
    fn from(v: Prime) -> Self {
        Self::Prime(v)
    }
}

impl<'a> From<&'a str> for Typ<'a> {
    fn from(s: &'a str) -> Self {
        match s {
            "i32" => Prime::I32.into(),
            "u8" => Prime::U8.into(),
            _ => Self::Name(s),
        }
    }
}

#[derive(Debug, PartialEq, Clone, Copy)]
pub enum Prime {
    I32,
    U8,
}

#[derive(Debug, PartialEq)]
pub enum Statement<'a> {
    Return(Expr<'a>),
    Call(Call<'a>),
}

impl<'a> From<Call<'a>> for Statement<'a> {
    fn from(v: Call<'a>) -> Self {
        Self::Call(v)
    }
}

#[derive(Debug, PartialEq)]
pub struct Call<'a> {
    pub name: &'a str,
    pub args: Vec<Expr<'a>>,
}

#[derive(Debug, PartialEq)]
pub enum Expr<'a> {
    Literal(Literal<'a>),
    Call(Call<'a>),
}

impl<'a> From<Call<'a>> for Expr<'a> {
    fn from(v: Call<'a>) -> Self {
        Self::Call(v)
    }
}

impl<'a> From<Literal<'a>> for Expr<'a> {
    fn from(v: Literal<'a>) -> Self {
        Self::Literal(v)
    }
}

#[derive(Debug, PartialEq, Clone, Copy)]
pub enum Literal<'a> {
    Int(u64),
    RawStr(&'a str),
}

impl<'a> From<u64> for Literal<'a> {
    fn from(v: u64) -> Self {
        Self::Int(v)
    }
}

pub fn parse<'a>(tokens: Vec<Token<'a>>) -> Result<Ast<'a>, ParseError<'a>> {
    let mut parser = Parser::new(tokens);
    parser.ast().map_err(|_| parser.error())
}

struct Parser<'a> {
    tokens: Vec<Token<'a>>,
    cursor: usize,
    err_cursor: usize,
    err_msgs: Vec<&'a str>,
}

type Res<T> = Result<T, ()>;

macro_rules! get_lexeme {
    ($self: ident, $pat:ident, $f:expr) => {
        if let $pat(val) = $self.tokens[$self.cursor].lexeme {
            $self.cursor += 1;
            Ok(val)
        } else {
            $self.fail($f);
            Err(())
        }
    };
}

impl<'a> Parser<'a> {
    fn new(tokens: Vec<Token<'a>>) -> Self {
        Self {
            cursor: 0,
            err_cursor: 0,
            err_msgs: Vec::new(),
            tokens,
        }
    }

    fn ast(&mut self) -> Res<Ast<'a>> {
        let ext_funs = self.many(Self::ext_fun);
        let funs = self.many(Self::fun);
        self.expect(Eof)?;
        Ok(Ast { ext_funs, funs })
    }

    fn ext_fun(&mut self) -> Res<ExtFun<'a>> {
        self.expect(Name("extern"))?;
        let header = self.header()?;
        self.expect(Semicolon)?;
        Ok(ExtFun { header })
    }

    fn many<T>(&mut self, parse: fn(&mut Self) -> Res<T>) -> Vec<T> {
        let mut res = Vec::new();
        while let Some(item) = self.maybe(parse) {
            res.push(item);
        }
        res
    }

    fn sep<T>(&mut self, parse: fn(&mut Self) -> Res<T>) -> Vec<T> {
        let mut res = Vec::new();
        match self.maybe(parse) {
            Some(item) => res.push(item),
            None => return res,
        }
        while let Some(item) = self.maybe(|p| {
            p.expect(Comma)?;
            parse(p)
        }) {
            res.push(item);
        }
        res
    }

    fn maybe<T>(&mut self, parse: impl Fn(&mut Self) -> Res<T>) -> Option<T> {
        let before = self.cursor;
        let res = parse(self).ok();
        if res.is_none() {
            self.cursor = before;
        }
        res
    }

    fn fun(&mut self) -> Res<Fun<'a>> {
        let header = self.header()?;
        self.expect(CurL)?;
        let body = self.many(Self::statement);
        self.expect(CurR)?;
        Ok(Fun { header, body })
    }

    fn header(&mut self) -> Res<Header<'a>> {
        self.expect(Name("fn"))?;
        let name = self.name()?;
        self.expect(ParL)?;
        let args = self.sep(Self::fun_arg);
        self.expect(ParR)?;
        self.expect(Name("i32"))?;
        Ok(Header { name, args })
    }

    fn fun_arg(&mut self) -> Res<(&'a str, Typ<'a>)> {
        let name = self.name()?;
        self.expect(Colon)?;
        let typ = self.typ()?;
        Ok((name, typ))
    }

    fn typ(&mut self) -> Res<Typ<'a>> {
        self.either(&[
            |p| {
                let name = p.name()?;
                Ok(name.into())
            },
            |p| {
                p.expect(Star)?;
                let typ = p.typ()?;
                Ok(Typ::Ptr(Box::new(typ)))
            },
        ])
    }

    fn either<T>(&mut self, parses: &[fn(&mut Self) -> Res<T>]) -> Res<T> {
        for parse in parses {
            if let Some(res) = self.maybe(*parse) {
                return Ok(res);
            }
        }
        Err(())
    }

    fn statement(&mut self) -> Res<Statement<'a>> {
        self.either(&[
            |p| {
                p.expect(Name("return"))?;
                let expr = p.expr()?;
                p.expect(Semicolon)?;
                Ok(Statement::Return(expr))
            },
            |p| {
                let call = p.call()?;
                p.expect(Semicolon)?;
                Ok(call.into())
            },
        ])
    }

    fn expr(&mut self) -> Res<Expr<'a>> {
        self.either(&[
            |p| {
                let literal = p.literal()?;
                Ok(literal.into())
            },
            |p| {
                let call = p.call()?;
                Ok(call.into())
            },
        ])
    }

    fn call(&mut self) -> Res<Call<'a>> {
        let name = self.name()?;
        self.expect(ParL)?;
        let args = self.sep(Self::expr);
        self.expect(ParR)?;
        Ok(Call { name, args })
    }

    fn literal(&mut self) -> Res<Literal<'a>> {
        self.either(&[
            |p| {
                let int = p.int()?;
                Ok(int.into())
            },
            |p| {
                let raw_str = p.raw_str()?;
                Ok(Literal::RawStr(raw_str))
            },
        ])
    }

    fn raw_str(&mut self) -> Res<&'a str> {
        get_lexeme!(self, RawStr, "<raw str>")
    }

    fn name(&mut self) -> Res<&'a str> {
        get_lexeme!(self, Name, "<name>")
    }

    fn int(&mut self) -> Res<u64> {
        get_lexeme!(self, Int, "<int>")
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
    use crate::{compile::read_file, lex::lex, parse::parse, source::meta};

    fn test_parse(name: &str) {
        let path = format!("examples/{name}.ok");
        let code = read_file(&path);
        let meta = meta(&path, &code);
        let tokens = lex(&code, &meta);
        parse(tokens).unwrap_or_else(|e| panic!("{e}"));
    }

    #[test]
    fn test_parse_empty() {
        test_parse("empty");
    }

    #[test]
    fn test_parse_simple_call() {
        test_parse("simple_call")
    }

    #[test]
    fn test_parse_simple_call_2() {
        test_parse("simple_call_2")
    }

    #[test]
    fn test_parse_var() {
        test_parse("var");
    }
}
