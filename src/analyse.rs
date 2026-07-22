use std::{collections::HashMap, iter::repeat_n};

use crate::ast::{Assign, Ast, Binary, Call, Expr, Field, Fun, If, Let, Literal, Statement, Var};

#[derive(Default, Clone, Copy)]
pub struct ExprInfo<'a> {
    pub typ_name: &'a str,
}

pub struct Info<'a> {
    pub exprs: Vec<ExprInfo<'a>>,
}

impl<'a> Info<'a> {
    fn new(ids: usize) -> Self {
        Self {
            exprs: repeat_n(ExprInfo::default(), ids).collect(),
        }
    }
}

pub fn analyse<'a>(ast: &Ast<'a>) -> Info<'a> {
    Analyser::new(ast.ids).analyse(ast)
}

struct Analyser<'a> {
    res: Info<'a>,
    vars: HashMap<&'a str, usize>,
}

impl<'a> Analyser<'a> {
    fn new(ids: usize) -> Self {
        Self {
            res: Info::new(ids),
            vars: HashMap::new(),
        }
    }

    fn analyse(mut self, ast: &Ast<'a>) -> Info<'a> {
        for fun in &ast.funs {
            self.fun(fun);
        }
        self.res
    }

    fn fun(&mut self, fun: &Fun<'a>) {
        for statement in &fun.body {
            self.statement(statement);
        }
    }

    fn statement(&mut self, statement: &Statement<'a>) {
        match statement {
            Statement::Return(expr) => self.expr(expr),
            Statement::Call(call) => self.call(call),
            Statement::Let(let_statement) => self.let_statement(let_statement),
            Statement::Assign(assign) => self.assign(assign),
            Statement::If(if_statement) => self.if_statement(if_statement),
            Statement::Loop(body) => self.loop_statement(body),
            Statement::Break => {}
            Statement::Continue => {}
        }
    }

    fn expr(&mut self, expr: &Expr<'a>) {
        match expr {
            Expr::Literal(literal) => self.literal(literal),
            Expr::Call(call) => self.call(call),
            Expr::Var(var) => self.var(var),
            Expr::Binary(binary) => self.binary(binary),
            Expr::Field(field) => self.field(field),
        }
    }

    fn literal(&mut self, literal: &Literal<'a>) {
        if let Literal::Str(s) = literal {
            self.res.exprs[s.id].typ_name = "str"
        }
    }

    fn call(&mut self, call: &Call<'a>) {
        for expr in &call.args {
            self.expr(expr)
        }
    }

    fn var(&mut self, var: &Var<'a>) {
        self.res.exprs[var.id] = self.res.exprs[self.vars[var.name]];
    }

    fn let_statement(&mut self, let_statement: &Let<'a>) {
        self.expr(&let_statement.expr);
        self.vars
            .insert(let_statement.name, let_statement.expr.id());
    }

    fn assign(&mut self, assign: &Assign<'a>) {
        self.expr(&assign.expr);
    }

    fn loop_statement(&mut self, body: &[Statement<'a>]) {
        for statement in body {
            self.statement(statement);
        }
    }

    fn binary(&mut self, binary: &Binary<'a>) {
        self.expr(&binary.left);
        self.expr(&binary.right);
    }

    fn field(&mut self, field: &Field<'a>) {
        self.expr(&field.parent);
    }

    fn if_statement(&mut self, if_statement: &If<'a>) {
        self.expr(&if_statement.condition);
        for statement in &if_statement.on_true {
            self.statement(statement);
        }
        for statement in &if_statement.on_false {
            self.statement(statement);
        }
    }
}
