mod codegen;
mod lex;
mod parse;
mod source;

use std::{env::args, fs::File, io::Read, process::exit};

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
        Some(path) => {
            let code = read_file(&path);
            let meta = meta(&path, &code);
            let tokens = lex(&code, &meta);
            let ast = parse(tokens).unwrap_or_else(|e| {
                eprintln!("{e}");
                exit(1)
            });
            gen_ir(ast, IR_PATH);
        }
        None => {
            eprintln!("{RED}error:{RESET} no source path given");
            exit(1)
        }
    }
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
