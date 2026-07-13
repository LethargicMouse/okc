mod generate;
mod lex;
mod parse;

use std::{
    fs::{File, create_dir_all},
    io::Read,
};

use crate::{generate::gen_ir, lex::lex, parse::parse};

fn main() {
    let code = read_file("resources/empty.ok");
    let tokens = lex(&code);
    let ast = parse(tokens);
    create_dir_all("build").unwrap();
    gen_ir(ast);
    let generated = read_file("build/out.ll");
    let expected = "define i32 @main() {\nentry:\nret i32 0\n}";
    assert_eq!(generated, expected);
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
    use crate::{
        lex::{
            Lexeme::{self, *},
            lex,
        },
        parse::{Ast, Expr, Fun, Statement, parse},
        read_file,
    };

    #[test]
    fn read_empty() {
        let code = read_file("resources/empty.ok");
        let actual = include_str!("../resources/empty.ok");
        assert_eq!(code, actual);
    }

    #[test]
    fn lex_empty() {
        let code = read_file("resources/empty.ok");
        let tokens = lex(&code);
        let empty_ok_lexemes: &[Lexeme] = &[
            Name("fn"),
            Name("main"),
            ParL,
            ParR,
            Name("i32"),
            CurL,
            Name("return"),
            Int(0),
            Semicolon,
            CurR,
            Eof,
        ];
        assert_eq!(
            tokens
                .iter()
                .map(|t| t.lexeme)
                .collect::<Vec<_>>()
                .as_slice(),
            empty_ok_lexemes
        )
    }

    #[test]
    fn parse_empty() {
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
}
