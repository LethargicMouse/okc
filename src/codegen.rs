use std::{collections::HashMap, process::exit};

use crate::{
    RED, RESET,
    parse::{Ast, Call, Expr, ExtFun, Fun, Header, Literal, Prime, Statement, Typ},
};
use inkwell::{
    builder::Builder,
    context::Context,
    module::Module,
    targets::TargetTriple,
    types::{BasicMetadataTypeEnum, FunctionType},
    values::{BasicValueEnum, FunctionValue, ValueKind},
};

pub const IR_PATH: &str = "build/out.ll";

pub fn gen_ir(ast: Ast, path: &str) {
    let context = Context::create();
    let mut generator = Generator::new(&context);
    generator.ast(ast);
    generator.module.print_to_file(path).unwrap_or_else(|e| {
        eprintln!("{RED}error:{RESET} failed to write to `{path}`: {e}");
        exit(1)
    })
}

struct Generator<'a> {
    context: &'a Context,
    module: Module<'a>,
    builder: Builder<'a>,
    funs: HashMap<&'a str, FunctionValue<'a>>,
    next_tmp: u32,
}

impl<'a> Generator<'a> {
    fn new(context: &'a Context) -> Self {
        Self {
            module: context.create_module("main"),
            builder: context.create_builder(),
            funs: HashMap::new(),
            context,
            next_tmp: 0,
        }
    }

    fn ast(&mut self, ast: Ast<'a>) {
        let triple = TargetTriple::create("x86_64-pc-linux-gnu");
        self.module.set_triple(&triple);
        for ext_fun in ast.ext_funs {
            self.ext_fun(ext_fun);
        }
        let fun_vals: Vec<_> = ast
            .funs
            .iter()
            .map(|fun| self.add_fun(&fun.header))
            .collect();
        for (fun, fun_val) in ast.funs.into_iter().zip(fun_vals) {
            self.fun(fun, fun_val);
        }
    }

    fn ext_fun(&mut self, ext_fun: ExtFun<'a>) {
        self.add_fun(&ext_fun.header);
    }

    fn add_fun(&mut self, header: &Header<'a>) -> FunctionValue<'a> {
        let fun_typ = self.fun_typ(header);
        let res = self.module.add_function(header.name, fun_typ, None);
        self.funs.insert(header.name, res);
        res
    }

    fn fun_typ(&self, header: &Header) -> FunctionType<'a> {
        let param_typs: Vec<BasicMetadataTypeEnum> = header
            .args
            .iter()
            .map(|(_, typ)| gen_typ(self.context, typ))
            .collect();
        self.context.i32_type().fn_type(&param_typs, false)
    }

    fn fun(&mut self, fun: Fun, fun_val: FunctionValue<'a>) {
        let basic_block = self.context.append_basic_block(fun_val, "entry");
        self.builder.position_at_end(basic_block);
        for statement in &fun.body {
            self.statement(statement);
        }
    }

    fn statement(&mut self, statement: &Statement) {
        match statement {
            Statement::Return(expr) => self.ret(expr),
            Statement::Call(call) => {
                self.call(call);
            }
            Statement::Let(_) => todo!(),
        }
    }

    fn ret(&mut self, expr: &Expr) {
        let val = self.expr(expr);
        self.builder.build_return(Some(&val)).unwrap();
    }

    fn expr(&mut self, expr: &Expr) -> BasicValueEnum<'a> {
        match expr {
            Expr::Literal(literal) => self.literal(literal),
            Expr::Call(call) => self.call(call).unwrap(),
            Expr::Var(_) => todo!(),
        }
    }

    fn literal(&mut self, literal: &Literal) -> BasicValueEnum<'a> {
        match literal {
            Literal::Int(n) => self.context.i32_type().const_int(*n, false).into(),
            Literal::RawStr(s) => {
                let tmp = self.new_tmp();
                self.builder
                    .build_global_string_ptr(s, &format!(".s{tmp}"))
                    .unwrap()
                    .as_pointer_value()
                    .into()
            }
        }
    }

    fn call(&mut self, call: &Call) -> Option<BasicValueEnum<'a>> {
        let tmp = self.new_tmp();
        let args: Vec<_> = call
            .args
            .iter()
            .map(|expr| self.expr(expr).into())
            .collect();
        let call = self
            .builder
            .build_direct_call(self.funs[call.name], &args, &format!("t{}", tmp))
            .unwrap();
        match call.try_as_basic_value() {
            ValueKind::Basic(val) => Some(val),
            ValueKind::Instruction(_) => None,
        }
    }

    fn new_tmp(&mut self) -> u32 {
        self.next_tmp += 1;
        self.next_tmp - 1
    }
}

fn gen_typ<'a>(context: &'a Context, typ: &Typ<'_>) -> BasicMetadataTypeEnum<'a> {
    match typ {
        Typ::Prime(prime) => prime_typ(context, prime),
        Typ::Ptr(_) => context.ptr_type(0.into()).into(),
        Typ::Name(_) => context.ptr_type(0.into()).into(),
    }
}

fn prime_typ<'a>(context: &'a Context, prime: &Prime) -> BasicMetadataTypeEnum<'a> {
    match prime {
        Prime::I32 => context.i32_type().into(),
        Prime::U8 => context.i8_type().into(),
    }
}

#[cfg(test)]
mod tests {
    use crate::{
        codegen::gen_ir, compile::read_file, lex::lex, parse::parse, run_command, source::meta,
    };
    use pretty_assertions::assert_eq;

    fn test_codegen(name: &str) {
        let input = format!("examples/{name}.ok");
        let output = format!("build/{name}.ll");
        run_command("rm", ["-f", &output]);
        let expected = read_file(&format!("examples_compiled/{name}.ll"));
        let code = read_file(&input);
        let meta = meta(&input, &code);
        let tokens = lex(&code, &meta);
        let ast = parse(tokens).unwrap();
        gen_ir(ast, &output);
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

    #[test]
    fn test_codegen_simple_call_2() {
        test_codegen("simple_call_2");
    }
}
