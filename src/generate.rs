use std::{
    fs::File,
    io::{self, Write},
    process::exit,
};

use crate::{
    RED, RESET,
    parse::{Ast, Expr, Statement},
};

pub fn gen_ir(ast: Ast) {
    try_gen_ir(ast).unwrap_or_else(|e| {
        eprintln!("{RED}error: failed to write to {RESET}`{IR_PATH}`{RED}: {e}");
        exit(1)
    })
}

pub const IR_PATH: &str = "build/out.ll";

fn try_gen_ir(ast: Ast) -> io::Result<()> {
    let mut file = File::create(IR_PATH)?;
    for fun in ast.funs {
        write!(file, "define i32 @{}() {{\nentry:", fun.name)?;
        for statement in fun.body {
            match statement {
                Statement::Return(expr) => {
                    write!(file, "\nret i32 ")?;
                    match expr {
                        Expr::Int(n) => write!(file, "{n}")?,
                    }
                }
            }
        }
        write!(file, "\n}}")?;
    }
    Ok(())
}
