mod lex;
mod parse;

use std::{fs::File, io::Read};

use crate::{
    lex::lex,
    parse::{Ast, Expr, Fun, Statement, parse},
};

fn main() {
    let code = read_file("resources/empty.ok");
    let tokens = lex(&code);
    let ast = parse(tokens);
    let empty_ast = Ast {
        funs: vec![Fun {
            name: "main",
            body: vec![Statement::Return(Expr::Int(0))],
        }],
    };
    assert_eq!(ast, empty_ast);
}

const RED: &str = "\x1b[0;31m";
const RESET: &str = "\x1b[0m";

fn read_file(path: &str) -> String {
    let mut file = File::open(path).unwrap();
    let mut res = String::new();
    file.read_to_string(&mut res).unwrap();
    res
}
