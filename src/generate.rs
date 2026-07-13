use std::{
    fs::File,
    io::{self, Write},
    process::exit,
};

use crate::{
    RED, RESET,
    parse::{Ast, Expr, Statement},
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
    for fun in ast.funs {
        write!(file, "\ndefine i32 @{}() {{\nentry:", fun.name)?;
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        lex::{Meta, lex},
        parse::parse,
        read_file,
    };
    use std::fs::create_dir_all;

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
        let expected = "\ndefine i32 @main() {\nentry:\nret i32 0\n}";
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
}
