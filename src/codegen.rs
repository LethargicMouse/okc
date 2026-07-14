use std::{
    fs::File,
    io::{self, Write},
    process::exit,
};

use crate::{
    RED, RESET,
    parse::{Ast, Expr, Fun, Statement},
};

pub fn gen_ir(ast: Ast, path: &str) {
    try_gen_ir(ast, path).unwrap_or_else(|e| {
        eprintln!("{RED}error: failed to write to {RESET}`{path}`{RED}: {e}");
        exit(1)
    })
}

pub const IR_PATH: &str = "build/out.ll";

fn try_gen_ir(ast: Ast, path: &str) -> io::Result<()> {
    let mut file = File::create(path)?;
    write!(file, "target triple = \"x86_64-pc-linux-gnu\"")?;
    for fun in ast.funs {
        gen_fun(&mut file, fun)?;
    }
    Ok(())
}

fn gen_fun<T: Write>(out: &mut T, fun: Fun) -> io::Result<()> {
    write!(out, "\ndefine i32 @{}() {{\nentry:", fun.name)?;
    for statement in fun.body {
        gen_statement(out, statement)?;
    }
    write!(out, "\n}}")
}

fn gen_statement<T: Write>(out: &mut T, statement: Statement) -> io::Result<()> {
    match statement {
        Statement::Return(expr) => {
            write!(out, "\nret i32 ")?;
            gen_expr(out, expr)
        }
    }
}

fn gen_expr<T: Write>(out: &mut T, expr: Expr) -> io::Result<()> {
    match expr {
        Expr::Int(n) => write!(out, "{n}"),
    }
}
