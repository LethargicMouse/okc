mod lex;

use std::{fs::File, io::Read};

use crate::lex::{
    Lexeme::{self, *},
    lex,
};

fn main() {
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

fn read_file(path: &str) -> String {
    let mut file = File::open(path).unwrap();
    let mut res = String::new();
    file.read_to_string(&mut res).unwrap();
    res
}

#[cfg(test)]
mod tests {

    #[test]
    fn lex_empty() {}
}
