use std::{fs::File, io::Read, process::exit};

use crate::{
    analyse::analyse,
    codegen::{IR_PATH, gen_ir},
    display::LogError,
    lex::lex,
    parse::parse,
    run_command,
    source::Source,
};

pub fn compile(path: &str) {
    let code = read_file(path);
    let source = Source::new(path, &code);
    let tokens = lex(&source);
    let ast = parse(tokens).unwrap_or_else(|e| {
        eprintln!("{e}");
        exit(1)
    });
    let info = analyse(&ast);
    gen_ir(ast, info, IR_PATH);
    run_command("clang", ["-o", "build/out", "build/out.ll"]);
}

pub fn read_file(path: &str) -> String {
    let mut file = File::open(path).unwrap_or_else(|e| {
        eprintln!("{LogError} failed to open `{path}`: {e}");
        exit(1)
    });
    let mut res = String::new();
    file.read_to_string(&mut res).unwrap_or_else(|e| {
        eprintln!("{LogError} failed to read `{path}`: {e}");
        exit(1)
    });
    res
}
