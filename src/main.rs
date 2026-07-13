mod codegen;
mod display_location;
mod lex;
mod parse;
mod source;

use std::{env::args, fmt::Display, fs::File, io::Read, process::exit};

use crate::{
    codegen::{IR_PATH, gen_ir},
    lex::lex,
    parse::parse,
    source::meta,
};

fn main() {
    let mut args = args();
    // skip exec name
    args.next();
    match args.next() {
        Some(path) => compile(&path),
        None => die("{RED}error:{RESET} no source path given"),
    }
}

fn compile(path: &str) {
    let code = read_file(path);
    let meta = meta(path, &code);
    let tokens = lex(&code, &meta);
    let ast = parse(tokens).unwrap_or_else(|e| die(e));
    gen_ir(ast, IR_PATH);
}

fn die(e: impl Display) -> ! {
    eprintln!("{e}");
    exit(1)
}

const RED: &str = "\x1b[0;31m";
const RESET: &str = "\x1b[0m";

fn read_file(path: &str) -> String {
    let mut file = File::open(path).unwrap();
    let mut res = String::new();
    file.read_to_string(&mut res).unwrap();
    res
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn read_empty() {
        let code = read_file("resources/empty.ok");
        let actual = include_str!("../resources/empty.ok");
        assert_eq!(code, actual);
    }
}
