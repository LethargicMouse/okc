use std::{collections::HashMap, process::exit};

use crate::{
    ast::{
        Assign, Ast, BinOp, Binary, Call, Expr, ExtFun, Fun, Header, If, Let, Literal, Prime,
        Statement, Typ,
    },
    display::LogError,
};
use inkwell::{
    IntPredicate,
    basic_block::BasicBlock,
    builder::Builder,
    context::Context,
    module::Module,
    targets::TargetTriple,
    types::{BasicMetadataTypeEnum, BasicTypeEnum, FunctionType},
    values::{BasicValueEnum, FunctionValue, PointerValue},
};

pub const IR_PATH: &str = "build/out.ll";

pub fn gen_ir(ast: Ast, path: &str) {
    let context = Context::create();
    let mut generator = Generator::new(&context);
    generator.ast(ast);
    generator.module.print_to_file(path).unwrap_or_else(|e| {
        eprintln!("{LogError} failed to write to `{path}`: {e}");
        exit(1)
    })
}

struct Generator<'a> {
    context: &'a Context,
    module: Module<'a>,
    builder: Builder<'a>,
    funs: HashMap<&'a str, FunctionValue<'a>>,
    vars: HashMap<&'a str, (PointerValue<'a>, BasicTypeEnum<'a>)>,
    next_tmp: u32,
    current_fun: Option<FunctionValue<'a>>,
    loop_block: Vec<BasicBlock<'a>>,
    after_loop: Vec<BasicBlock<'a>>,
}

impl<'a> Generator<'a> {
    fn new(context: &'a Context) -> Self {
        Self {
            module: context.create_module("main"),
            builder: context.create_builder(),
            funs: HashMap::new(),
            context,
            next_tmp: 0,
            vars: HashMap::new(),
            current_fun: None,
            after_loop: Vec::new(),
            loop_block: Vec::new(),
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
            self.current_fun = Some(fun_val);
            self.fun(fun);
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
            .params
            .iter()
            .map(|param| self.typ(&param.typ))
            .collect();
        self.context.i32_type().fn_type(&param_typs, false)
    }

    fn fun(&mut self, fun: Fun<'a>) {
        self.vars.clear();
        let basic_block = self
            .context
            .append_basic_block(self.current_fun.unwrap(), "entry");
        self.builder.position_at_end(basic_block);
        for statement in &fun.body {
            self.statement(statement);
        }
    }

    fn statement(&mut self, statement: &Statement<'a>) {
        match statement {
            Statement::Return(expr) => self.ret(expr),
            Statement::Call(call) => {
                self.call(call);
            }
            Statement::Let(let_statement) => self.gen_let(let_statement),
            Statement::Assign(assign) => self.assign(assign),
            Statement::If(if_statement) => self.gen_if(if_statement),
            Statement::Loop(body) => self.gen_loop(body),
            Statement::Break => self.gen_break(),
            Statement::Continue => self.gen_continue(),
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
            Expr::Var(n) => self.var(n),
            Expr::Binary(binary) => self.binary(binary),
            Expr::Field(_) => todo!(),
        }
    }

    fn literal(&mut self, literal: &Literal) -> BasicValueEnum<'a> {
        match literal {
            Literal::Int(n) => self.context.i32_type().const_int(*n, false).into(),
            Literal::RawStr(s) => self.raw_str(&unescape(s)),
            Literal::Str(s) => self.str(&unescape(s)),
        }
    }

    fn raw_str(&mut self, s: &str) -> BasicValueEnum<'a> {
        let tmp = self.new_tmp();
        self.builder
            .build_global_string_ptr(s, &format!(".s{tmp}"))
            .unwrap()
            .as_pointer_value()
            .into()
    }

    fn str(&mut self, s: &str) -> BasicValueEnum<'a> {
        let typ = self.context.struct_type(
            &[
                self.context.ptr_type(0.into()).into(),
                self.context.i64_type().into(),
            ],
            false,
        );
        let tmp = self.new_tmp();
        let res = self.builder.build_alloca(typ, &format!("t{tmp}")).unwrap();
        let ptr = self.raw_str(s);
        let tmp = self.new_tmp();
        let dst = self
            .builder
            .build_struct_gep(typ, res, 0, &format!("t{tmp}"))
            .unwrap();
        self.builder.build_store(dst, ptr).unwrap();
        let len = s.len();
        let tmp = self.new_tmp();
        let dst = self
            .builder
            .build_struct_gep(typ, res, 0, &format!("t{tmp}"))
            .unwrap();
        self.builder
            .build_store(dst, self.context.i64_type().const_int(len as u64, false))
            .unwrap();
        res.into()
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
        call.try_as_basic_value().basic()
    }

    fn new_tmp(&mut self) -> u32 {
        self.next_tmp += 1;
        self.next_tmp - 1
    }

    fn gen_let(&mut self, let_statement: &Let<'a>) {
        let val = self.expr(&let_statement.expr);
        let typ = val.get_type();
        let tmp = self.new_tmp();
        let ptr = self.builder.build_alloca(typ, &format!("t{tmp}")).unwrap();
        self.builder.build_store(ptr, val).unwrap();
        self.vars.insert(let_statement.name, (ptr, typ));
    }

    fn assign(&mut self, assign: &Assign) {
        let ptr = self.vars[assign.name].0;
        let val = self.expr(&assign.expr);
        self.builder.build_store(ptr, val).unwrap();
    }

    fn var(&mut self, n: &str) -> BasicValueEnum<'a> {
        let (ptr, typ) = self.vars[n];
        let tmp = self.new_tmp();
        self.builder
            .build_load(typ, ptr, &format!("t{tmp}"))
            .unwrap()
    }

    fn binary(&mut self, binary: &Binary) -> BasicValueEnum<'a> {
        let left = self.expr(&binary.left);
        let right = self.expr(&binary.right);
        let tmp = self.new_tmp();
        let tmp = format!("t{tmp}");
        let op = match binary.op {
            BinOp::Add => Builder::build_int_add,
            BinOp::Mul => Builder::build_int_mul,
            BinOp::Div => Builder::build_int_signed_div,
            BinOp::Rem => Builder::build_int_signed_rem,
            BinOp::Sub => Builder::build_int_sub,
            BinOp::Equ => {
                |b: &Builder<'a>, l, r, t: &str| b.build_int_compare(IntPredicate::EQ, l, r, t)
            }
        };
        op(
            &self.builder,
            left.into_int_value(),
            right.into_int_value(),
            &tmp,
        )
        .unwrap()
        .into()
    }

    fn gen_if(&mut self, if_statement: &If<'a>) {
        let condition = self.expr(&if_statement.condition);
        let on_true = self.new_block();
        let on_false = self.new_block();
        let after = self.new_block();
        self.builder
            .build_conditional_branch(condition.into_int_value(), on_true, on_false)
            .unwrap();
        self.builder.position_at_end(on_true);
        for statement in &if_statement.on_true {
            self.statement(statement);
        }
        self.builder.build_unconditional_branch(after).unwrap();
        self.builder.position_at_end(on_false);
        for statement in &if_statement.on_false {
            self.statement(statement);
        }
        self.builder.build_unconditional_branch(after).unwrap();
        self.builder.position_at_end(after);
    }

    fn new_block(&mut self) -> BasicBlock<'a> {
        let tmp = self.new_tmp();
        self.context
            .append_basic_block(self.current_fun.unwrap(), &format!("s{tmp}"))
    }

    fn gen_loop(&mut self, body: &[Statement<'a>]) {
        let loop_block = self.new_block();
        let after = self.new_block();
        self.builder.build_unconditional_branch(loop_block).unwrap();
        self.builder.position_at_end(loop_block);
        self.loop_block.push(loop_block);
        self.after_loop.push(after);
        for statement in body {
            self.statement(statement);
        }
        self.loop_block.pop();
        self.after_loop.pop();
        self.builder.build_unconditional_branch(loop_block).unwrap();
        self.builder.position_at_end(after);
    }

    fn gen_break(&self) {
        self.builder
            .build_unconditional_branch(*self.after_loop.last().unwrap())
            .unwrap();
    }

    fn gen_continue(&self) {
        self.builder
            .build_unconditional_branch(*self.loop_block.last().unwrap())
            .unwrap();
    }

    fn typ(&self, typ: &Typ<'_>) -> BasicMetadataTypeEnum<'a> {
        match typ {
            Typ::Prime(prime) => self.prime(prime),
            Typ::Ptr(_) => self.context.ptr_type(0.into()).into(),
            Typ::Name(_) => self.context.ptr_type(0.into()).into(),
        }
    }

    fn prime(&self, prime: &Prime) -> BasicMetadataTypeEnum<'a> {
        match prime {
            Prime::I32 => self.context.i32_type().into(),
            Prime::U8 => self.context.i8_type().into(),
        }
    }
}

fn unescape(s: &str) -> String {
    let mut res = String::new();
    let mut chars = s.chars();
    while let Some(c) = chars.next() {
        res.push(if c == '\\' {
            match chars.next().unwrap() {
                'n' => '\n',
                c => unreachable!("{c}"),
            }
        } else {
            c
        });
    }
    res
}

#[cfg(test)]
mod tests {
    use crate::{
        codegen::gen_ir, compile::read_file, lex::lex, parse::parse, run_command, source::Source,
    };
    use pretty_assertions::assert_eq;

    fn test_codegen(name: &str) {
        let input = format!("examples/{name}.ok");
        let output = format!("build/{name}.ll");
        run_command("rm", ["-f", &output]);
        let expected = read_file(&format!("examples_compiled/{name}.ll"));
        let code = read_file(&input);
        let source = Source::new(&input, &code);
        let tokens = lex(&source);
        let ast = match parse(tokens) {
            Ok(ast) => ast,
            // test_parse will fail, not running test_codegen
            Err(_) => return,
        };
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

    #[test]
    fn test_codegen_var() {
        test_codegen("var")
    }

    #[test]
    fn test_codegen_var_assign() {
        test_codegen("var_assign")
    }

    #[test]
    fn test_codegen_add() {
        test_codegen("add")
    }

    #[test]
    fn test_codegen_add_mul() {
        test_codegen("add_mul")
    }

    #[test]
    fn test_codegen_add_mul_div() {
        test_codegen("add_mul_div")
    }

    #[test]
    fn test_codegen_add_mul_div_sub() {
        test_codegen("add_mul_div_sub")
    }

    #[test]
    fn test_codegen_if() {
        test_codegen("if")
    }

    #[test]
    fn test_codegen_fizzbuzz() {
        test_codegen("fizzbuzz")
    }
}
