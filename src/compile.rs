use std::{fs::File, io::Read};

use crate::{
    codegen::{IR_PATH, gen_ir},
    die,
    lex::lex,
    parse::parse,
    run_command,
    source::meta,
};

pub fn compile(path: &str) {
    let code = read_file(path);
    let meta = meta(path, &code);
    let tokens = lex(&code, &meta);
    let ast = parse(tokens).unwrap_or_else(|e| die(e));
    gen_ir(ast, IR_PATH);
    run_command("clang", ["-o", "build/out", "build/out.ll"]);
}

pub fn read_file(path: &str) -> String {
    let mut file = File::open(path).unwrap();
    let mut res = String::new();
    file.read_to_string(&mut res).unwrap();
    res
}
