use std::{fs::File, io::Read};

use crate::{
    codegen::{IR_PATH, gen_ir},
    die,
    lex::lex,
    parse::parse,
    run_command,
    source::meta,
};

// tested
pub fn compile(path: &str) {
    let code = read_file(path);
    let meta = meta(path, &code);
    let tokens = lex(&code, &meta);
    let ast = parse(tokens).unwrap_or_else(|e| die(e));
    gen_ir(ast, IR_PATH);
    run_command("clang", ["-o", "build/out", "build/out.ll"]);
}

// tested
pub fn read_file(path: &str) -> String {
    let mut file = File::open(path).unwrap();
    let mut res = String::new();
    file.read_to_string(&mut res).unwrap();
    res
}

#[cfg(test)]
mod tests {
    use crate::codegen::tests::EMPTY_IR;

    use super::*;

    #[test]
    fn test_read_empty() {
        let code = read_file("resources/empty.ok");
        let actual = include_str!("../resources/empty.ok");
        assert_eq!(code, actual);
    }

    #[test]
    fn test_compile() {
        compile("resources/empty.ok");
        assert_eq!(EMPTY_IR, read_file(IR_PATH))
    }
}
