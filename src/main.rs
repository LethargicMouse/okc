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

#[cfg(test)]
mod tests {
    use crate::{
        lex::{
            Lexeme::{self, *},
            lex,
        },
        read_file,
    };

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
}
