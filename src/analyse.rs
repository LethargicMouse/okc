use crate::parse::{Ast, Call, Expr, ExtFun, Fun, Header, Literal, Prime, Statement, Typ};

pub struct GoodAst<'a> {
    pub ext_funs: Vec<ExtFun<'a>>,
    pub funs: Vec<GoodFun<'a>>,
}

pub struct GoodFun<'a> {
    pub header: Header<'a>,
    pub body: Vec<GoodStatement<'a>>,
}

pub struct GoodCall<'a> {
    pub name: &'a str,
    pub args: Vec<GoodExpr<'a>>,
}

pub enum GoodStatement<'a> {
    Return(GoodExpr<'a>),
    Call(GoodCall<'a>),
}

impl<'a> From<GoodCall<'a>> for GoodStatement<'a> {
    fn from(v: GoodCall<'a>) -> Self {
        Self::Call(v)
    }
}

pub enum GoodExpr<'a> {
    Literal(Literal<'a>, Typ<'a>),
}

impl<'a> GoodExpr<'a> {
    pub fn typ(&self) -> &Typ<'a> {
        match self {
            GoodExpr::Literal(_, typ) => typ,
        }
    }
}

pub fn analyse<'a>(ast: Ast<'a>) -> GoodAst<'a> {
    GoodAst {
        ext_funs: ast.ext_funs,
        funs: ast.funs.into_iter().map(|f| analyse_fun(f)).collect(),
    }
}

fn analyse_fun<'a>(fun: Fun<'a>) -> GoodFun<'a> {
    GoodFun {
        header: fun.header,
        body: fun.body.into_iter().map(|s| analyse_statement(s)).collect(),
    }
}

fn analyse_statement<'a>(statement: Statement<'a>) -> GoodStatement<'a> {
    match statement {
        Statement::Return(expr) => GoodStatement::Return(analyse_expr(expr)),
        Statement::Call(call) => analyse_call(call).into(),
    }
}

fn analyse_call<'a>(call: Call<'a>) -> GoodCall<'a> {
    GoodCall {
        name: call.name,
        args: call
            .args
            .into_iter()
            .map(|expr| analyse_expr(expr))
            .collect(),
    }
}

fn analyse_expr<'a>(expr: Expr<'a>) -> GoodExpr<'a> {
    match expr {
        Expr::Literal(literal) => GoodExpr::Literal(literal, get_literal_typ(literal)),
    }
}

fn get_literal_typ(literal: Literal<'_>) -> Typ<'_> {
    match literal {
        Literal::Int(_) => Prime::I32.into(),
        Literal::RawStr(_) => Typ::Ptr(Box::new(Prime::U8.into())),
    }
}
