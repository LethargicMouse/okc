use std::{
    fs::File,
    io::{self, Write},
    process::exit,
};

use crate::{
    RED, RESET,
    analyse::{GoodAst, GoodCall, GoodExpr, GoodFun, GoodStatement},
    parse::{ExtFun, Literal, Prime, Typ},
};

pub fn gen_ir(ast: GoodAst, path: &str) {
    Generator::default().ast(ast, path).unwrap_or_else(|e| {
        eprintln!("{RED}error: failed to write to {RESET}`{path}`{RED}: {e}");
        exit(1)
    })
}

#[derive(Default)]
struct Generator<'a> {
    strs: Vec<&'a str>,
}

pub const IR_PATH: &str = "build/out.ll";

impl<'a> Generator<'a> {
    fn ast(mut self, ast: GoodAst<'a>, path: &str) -> io::Result<()> {
        let mut file = File::create(path)?;
        write!(file, "target triple = \"x86_64-pc-linux-gnu\"")?;
        for ext_fun in ast.ext_funs {
            gen_ext_fun(&mut file, ext_fun)?;
        }
        for fun in ast.funs {
            self.fun(&mut file, fun)?;
        }
        for (i, s) in self.strs.into_iter().enumerate() {
            gen_str(&mut file, i, s)?;
        }
        writeln!(file)
    }

    fn fun(&mut self, out: &mut impl Write, fun: GoodFun<'a>) -> io::Result<()> {
        write!(out, "\ndefine i32 @{}() {{\nentry:", fun.header.name)?;
        for statement in fun.body {
            self.statement(out, statement)?;
        }
        write!(out, "\n}}")
    }

    fn statement(&mut self, out: &mut impl Write, statement: GoodStatement<'a>) -> io::Result<()> {
        match statement {
            GoodStatement::Return(expr) => {
                write!(out, "\nret ")?;
                self.expr(out, expr)
            }
            GoodStatement::Call(call) => {
                writeln!(out)?;
                self.call(out, call)
            }
        }
    }

    fn call(&mut self, out: &mut impl Write, call: GoodCall<'a>) -> io::Result<()> {
        write!(out, "call i32 (")?;
        if let Some(expr) = call.args.first() {
            gen_typ(out, expr.typ())?;
            for expr in &call.args[1..] {
                write!(out, ",")?;
                gen_typ(out, expr.typ())?;
            }
        }
        write!(out, ") @{}(", call.name)?;
        for (i, expr) in call.args.into_iter().enumerate() {
            if i != 0 {
                write!(out, ", ")?;
            }
            self.expr(out, expr)?;
        }
        write!(out, ")")
    }

    fn expr(&mut self, out: &mut impl Write, expr: GoodExpr<'a>) -> io::Result<()> {
        match expr {
            GoodExpr::Literal(literal, typ) => {
                gen_typ(out, &typ)?;
                write!(out, " ")?;
                self.literal(out, literal)
            }
        }
    }

    fn literal(&mut self, out: &mut impl Write, literal: Literal<'a>) -> io::Result<()> {
        match literal {
            Literal::Int(n) => write!(out, "{n}"),
            Literal::RawStr(s) => {
                self.strs.push(s);
                write!(out, "@.str{}", self.strs.len() - 1)
            }
        }
    }
}

fn gen_str(out: &mut impl Write, i: usize, s: &str) -> io::Result<()> {
    write!(
        out,
        "\n@.str{i} = private unnamed_addr constant [{} x i8] c\"{s}\\00\", align 1",
        s.len() + 1
    )
}

fn gen_ext_fun(out: &mut impl Write, ext_fun: ExtFun) -> io::Result<()> {
    write!(out, "\ndeclare i32 @{}(", ext_fun.header.name)?;
    if let Some((_, typ)) = ext_fun.header.args.first() {
        gen_typ(out, typ)?;
        for (_, typ) in &ext_fun.header.args[1..] {
            write!(out, ",")?;
            gen_typ(out, typ)?;
        }
    }
    write!(out, ")")
}

fn gen_typ(out: &mut impl Write, typ: &Typ) -> io::Result<()> {
    match typ {
        Typ::Prime(prime) => gen_prime(out, prime),
        Typ::Ptr(_) | Typ::Name(_) => write!(out, "ptr"),
    }
}

fn gen_prime(out: &mut impl Write, prime: &Prime) -> io::Result<()> {
    match prime {
        Prime::I32 => write!(out, "i32"),
        Prime::U8 => write!(out, "i8"),
    }
}

#[cfg(test)]
mod tests {
    use crate::{
        analyse::analyse, codegen::gen_ir, compile::read_file, lex::lex, parse::parse, source::meta,
    };
    use pretty_assertions::assert_eq;

    fn test_codegen(name: &str) {
        let input = format!("examples/{name}.ok");
        let output = format!("build/{name}.ll");
        let expected = read_file(&format!("examples_compiled/{name}.ll"));
        let code = read_file(&input);
        let meta = meta(&input, &code);
        let tokens = lex(&code, &meta);
        let ast = parse(tokens).unwrap();
        let good_ast = analyse(ast);
        gen_ir(good_ast, &output);
        let found = read_file(&output);
        assert_eq!(found, expected)
    }

    #[test]
    fn test_codegen_empty() {
        test_codegen("empty");
    }

    #[test]
    fn test_codegen_simple_call() {
        test_codegen("simple_call");
    }
}
