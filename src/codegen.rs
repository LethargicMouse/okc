use std::{
    fs::File,
    io::{self, Write},
    process::exit,
};

use crate::{
    RED, RESET,
    parse::{Ast, Expr, Fun, Statement},
};

// tested
pub fn gen_ir(ast: Ast, path: &str) {
    try_gen_ir(ast, path).unwrap_or_else(|e| {
        eprintln!("{RED}error: failed to write to {RESET}`{path}`{RED}: {e}");
        exit(1)
    })
}

pub const IR_PATH: &str = "build/out.ll";

// tested
fn try_gen_ir(ast: Ast, path: &str) -> io::Result<()> {
    let mut file = File::create(path)?;
    for fun in ast.funs {
        gen_fun(&mut file, fun)?;
    }
    Ok(())
}

// tested
fn gen_fun<T: Write>(out: &mut T, fun: Fun) -> io::Result<()> {
    write!(out, "\ndefine i32 @{}() {{\nentry:", fun.name)?;
    for statement in fun.body {
        gen_statement(out, statement)?;
    }
    write!(out, "\n}}")
}

// tested
fn gen_statement<T: Write>(out: &mut T, statement: Statement) -> io::Result<()> {
    match statement {
        Statement::Return(expr) => {
            write!(out, "\nret i32 ")?;
            gen_expr(out, expr)
        }
    }
}

// tested
fn gen_expr<T: Write>(out: &mut T, expr: Expr) -> io::Result<()> {
    match expr {
        Expr::Int(n) => write!(out, "{n}"),
    }
}

#[cfg(test)]
pub mod tests {
    use super::*;
    use crate::{lex::lex, parse::parse, read_file, source::Meta};
    use std::fs::create_dir_all;

    pub const EMPTY_IR: &str = "\ndefine i32 @main() {\nentry:\nret i32 0\n}";

    #[test]
    fn generate_empty() {
        let code = read_file("resources/empty.ok");
        let meta = Meta {
            name: "resources/empty.ok",
            lines: code.lines().collect(),
        };
        let tokens = lex(&code, &meta);
        let ast = parse(tokens).unwrap_or_else(|e| panic!("{e}"));
        create_dir_all("build").unwrap();
        gen_ir(ast, "build/test_empty.ll");
        let generated = read_file("build/test_empty.ll");
        let expected = EMPTY_IR;
        assert_eq!(generated, expected);
    }

    #[test]
    fn generate_two_funs() {
        let code = read_file("resources/two_funs.ok");
        let meta = Meta {
            name: "resources/two_funs.ok",
            lines: code.lines().collect(),
        };
        let tokens = lex(&code, &meta);
        let ast = parse(tokens).unwrap_or_else(|e| panic!("{e}"));
        create_dir_all("build").unwrap();
        gen_ir(ast, "build/test_two_funs.ll");
        let expected = "\ndefine i32 @fun_1() {\nentry:\nret i32 123\n}\ndefine i32 @__fun_n2_() {\nentry:\nret i32 321\nret i32 444\n}";
        let generated = read_file("build/test_two_funs.ll");
        assert_eq!(expected, generated)
    }

    #[test]
    fn test_gen_fun_empty() -> io::Result<()> {
        let fun = Fun {
            name: "hello",
            body: vec![],
        };
        let mut out = Vec::new();
        let expected = "\ndefine i32 @hello() {\nentry:\n}".to_owned();
        gen_fun(&mut out, fun)?;
        assert_eq!(expected, String::from_utf8(out).unwrap());
        Ok(())
    }

    #[test]
    fn test_gen_statement() -> io::Result<()> {
        let statement = Statement::Return(Expr::Int(123));
        let mut out = Vec::new();
        let expected = "\nret i32 123".to_owned();
        gen_statement(&mut out, statement)?;
        assert_eq!(expected, String::from_utf8(out).unwrap());
        Ok(())
    }

    #[test]
    fn test_expr() -> io::Result<()> {
        let expr = Expr::Int(321);
        let mut out = Vec::new();
        let expected = "321".to_owned();
        gen_expr(&mut out, expr)?;
        assert_eq!(expected, String::from_utf8(out).unwrap());
        Ok(())
    }
}
