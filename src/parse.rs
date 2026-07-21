use std::{cmp::Ordering, fmt::Display};

use crate::{
    ast::*,
    display::LogError,
    lex::{
        Lexeme::{self, *},
        Token,
    },
    source::Location,
};

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
    ($self: ident, $pat:ident) => {
        if let $pat(val) = $self.tokens[$self.cursor].lexeme {
            $self.cursor += 1;
            Ok(val)
        } else {
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
                let name = p.name_()?;
                Ok(name.into())
            },
            |p| {
                p.expect_(Star)?;
                let typ = p.typ()?;
                Ok(Typ::Ptr(Box::new(typ)))
            },
        ])
        .inspect_err(|_| self.fail("<type>"))
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
                p.expect_(Name("let"))?;
                let name = p.name()?;
                p.expect(Equal)?;
                let expr = p.expr()?;
                p.expect(Semicolon)?;
                Ok(Let { name, expr }.into())
            },
            |p| {
                p.expect_(Name("return"))?;
                let expr = p.expr()?;
                p.expect(Semicolon)?;
                Ok(Statement::Return(expr))
            },
            |p| {
                let name = p.name_()?;
                p.expect(Equal)?;
                let expr = p.expr()?;
                p.expect(Semicolon)?;
                Ok(Assign { name, expr }.into())
            },
            |p| {
                let call = p.call_()?;
                p.expect(Semicolon)?;
                Ok(call.into())
            },
        ])
        .inspect_err(|_| self.fail("<statement>"))
    }

    fn expr(&mut self) -> Res<Expr<'a>> {
        self.expr_prior(0)
    }

    fn expr_prior(&mut self, prior: u8) -> Res<Expr<'a>> {
        let mut res = self.expr_atom()?;
        while let Some((op, expr)) = self.maybe(|p| {
            let op = p.bin_op_()?;
            let expr = p.expr_prior(get_prior(op))?;
            Ok((op, expr))
        }) {
            res = Binary {
                left: res,
                right: expr,
                op,
            }
            .into();
        }
        Ok(res)
    }

    fn bin_op_(&mut self) -> Res<BinOp> {
        self.either(&[
            |p| {
                p.expect_(Plus)?;
                Ok(BinOp::Add)
            },
            |p| {
                p.expect_(Star)?;
                Ok(BinOp::Mul)
            },
        ])
    }

    fn expr_atom(&mut self) -> Res<Expr<'a>> {
        self.either(&[
            |p| {
                let literal = p.literal_()?;
                Ok(literal.into())
            },
            |p| {
                let call = p.call_()?;
                Ok(call.into())
            },
            |p| {
                let name = p.name_()?;
                Ok(Expr::Var(name))
            },
        ])
        .inspect_err(|_| self.fail("<expr>"))
    }

    fn call_(&mut self) -> Res<Call<'a>> {
        let name = self.name_()?;
        self.expect(ParL)?;
        let args = self.sep(Self::expr);
        self.expect(ParR)?;
        Ok(Call { name, args })
    }

    fn literal_(&mut self) -> Res<Literal<'a>> {
        self.either(&[
            |p| {
                let int = p.int_()?;
                Ok(int.into())
            },
            |p| {
                let raw_str = p.raw_str_()?;
                Ok(Literal::RawStr(raw_str))
            },
        ])
    }

    fn raw_str_(&mut self) -> Res<&'a str> {
        get_lexeme!(self, RawStr)
    }

    fn name(&mut self) -> Res<&'a str> {
        self.name_().inspect_err(|_| self.fail("<name>"))
    }

    fn name_(&mut self) -> Res<&'a str> {
        get_lexeme!(self, Name)
    }

    fn int_(&mut self) -> Res<u64> {
        get_lexeme!(self, Int)
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
        self.expect_(lexeme)
            .inspect_err(|_| self.fail(lexeme.describe()))
    }

    fn expect_(&mut self, lexeme: Lexeme<'a>) -> Res<()> {
        if self.tokens[self.cursor].lexeme == lexeme {
            self.cursor += 1;
            Ok(())
        } else {
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

#[derive(Debug)]
pub struct ParseError<'a> {
    location: Location<'a>,
    msgs: Vec<&'a str>,
}

impl Display for ParseError<'_> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "{LogError} failed to parse {}\n  expected:",
            self.location
        )?;
        for msg in &self.msgs {
            write!(f, "\n    {msg}")?;
        }
        Ok(())
    }
}

fn get_prior(bin_op: BinOp) -> u8 {
    match bin_op {
        BinOp::Add => 0,
        BinOp::Mul => 1,
    }
}

#[cfg(test)]
mod tests {
    use crate::{compile::read_file, lex::lex, parse::parse, source::Source};

    fn test_parse(name: &str) {
        let path = format!("examples/{name}.ok");
        let code = read_file(&path);
        let source = Source::new(&path, &code);
        let tokens = lex(&source);
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

    #[test]
    fn test_parse_var_assign() {
        test_parse("var_assign");
    }

    #[test]
    fn test_parse_add() {
        test_parse("add");
    }

    #[test]
    fn test_parse_add_mul() {
        test_parse("add_mul")
    }
}
