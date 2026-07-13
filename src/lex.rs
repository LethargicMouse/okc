use Lexeme::*;

pub fn lex(code: &str) -> Vec<Token<'_>> {
    let mut res = Vec::new();
    let mut lexer = Lexer::new(code);
    lexer.populate(&mut res);
    res
}

pub struct Token<'a> {
    pub lexeme: Lexeme<'a>,
}

#[derive(Debug, PartialEq, Clone, Copy)]
pub enum Lexeme<'a> {
    Name(&'a str),
    Int(i64),
    ParL,
    ParR,
    CurL,
    CurR,
    Semicolon,
    Eof,
    Error,
}
impl<'a> Lexeme<'a> {
    pub fn describe(&self) -> &'a str {
        match self {
            Name(n) => n,
            ParL => "(",
            ParR => ")",
            CurL => "{",
            CurR => "}",
            Semicolon => ";",
            Eof => "<eof>",
            _ => unreachable!(),
        }
    }
}

struct Lexer<'a> {
    code: &'a str,
}

impl<'a> Lexer<'a> {
    pub fn new(code: &'a str) -> Self {
        Self { code }
    }

    fn token(&mut self, lexeme: Lexeme<'a>, len: usize) -> Token<'a> {
        self.code = &self.code[len..];
        Token { lexeme }
    }

    fn skip_spaces(&mut self) {
        self.code = self.code.trim_start();
    }

    fn populate(&mut self, res: &mut Vec<Token<'a>>) {
        let lex_list = [
            ("(", ParL),
            (")", ParR),
            ("{", CurL),
            ("}", CurR),
            (";", Semicolon),
        ];
        'main: loop {
            self.skip_spaces();
            if self.code.is_empty() {
                res.push(Token { lexeme: Eof });
                break;
            }
            for (pattern, lexeme) in lex_list {
                if self.code.starts_with(pattern) {
                    res.push(self.token(lexeme, pattern.len()));
                    continue 'main;
                }
            }
            let c = self.code.chars().next().unwrap();
            if c.is_alphabetic() || c == '_' {
                let name = self.take_while(|c| c.is_alphanumeric() || *c == '_');
                res.push(self.token(Name(name), name.len()));
                continue 'main;
            }
            if c.is_ascii_digit() {
                let int = self.take_while(|c| c.is_ascii_digit());
                res.push(self.token(Int(int.parse().unwrap()), int.len()));
                continue 'main;
            }
            res.push(self.token(Error, 1));
            break;
        }
    }

    fn take_while(&self, predicate: fn(&char) -> bool) -> &'a str {
        &self.code[..self.code.chars().take_while(predicate).count()]
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::read_file;

    fn mk_lexemes(code: &str) -> Vec<Lexeme<'_>> {
        lex(code).iter().map(|t| t.lexeme).collect()
    }

    #[test]
    fn lex_empty() {
        let code = read_file("resources/empty.ok");
        let tokens = mk_lexemes(&code);
        let empty_ok_lexemes = vec![
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
        assert_eq!(empty_ok_lexemes, tokens)
    }

    #[test]
    fn lex_no_space() {
        let code = "george){(}((123);}";
        let expected = vec![
            Name("george"),
            ParR,
            CurL,
            ParL,
            CurR,
            ParL,
            ParL,
            Int(123),
            ParR,
            Semicolon,
            CurR,
            Eof,
        ];
        let found = mk_lexemes(code);
        assert_eq!(expected, found)
    }

    #[test]
    fn lex_wrong_midtext() {
        let code = "george){($}((123);}";
        let expected = vec![Name("george"), ParR, CurL, ParL, Error];
        let found = mk_lexemes(code);
        assert_eq!(expected, found)
    }

    #[test]
    fn lex_spaced() {
        let code = "george is\nthe\tauthor \n\t  \t\n\n\t ;\n   \n";
        let expected = vec![
            Name("george"),
            Name("is"),
            Name("the"),
            Name("author"),
            Semicolon,
            Eof,
        ];
        let found = mk_lexemes(code);
        assert_eq!(expected, found)
    }
}
