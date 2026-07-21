pub struct Ast<'a> {
    pub ext_funs: Vec<ExtFun<'a>>,
    pub funs: Vec<Fun<'a>>,
}

pub struct ExtFun<'a> {
    pub header: Header<'a>,
}

pub struct Fun<'a> {
    pub header: Header<'a>,
    pub body: Vec<Statement<'a>>,
}

pub struct Header<'a> {
    pub name: &'a str,
    pub args: Vec<(&'a str, Typ<'a>)>,
}

pub enum Typ<'a> {
    Prime(Prime),
    Ptr(Box<Typ<'a>>),
    Name(&'a str),
}

impl<'a> From<Prime> for Typ<'a> {
    fn from(v: Prime) -> Self {
        Self::Prime(v)
    }
}

impl<'a> From<&'a str> for Typ<'a> {
    fn from(s: &'a str) -> Self {
        match s {
            "i32" => Prime::I32.into(),
            "u8" => Prime::U8.into(),
            _ => Self::Name(s),
        }
    }
}

pub enum Prime {
    I32,
    U8,
}

pub struct Let<'a> {
    pub name: &'a str,
    pub expr: Expr<'a>,
}

pub struct Assign<'a> {
    pub name: &'a str,
    pub expr: Expr<'a>,
}

pub enum Statement<'a> {
    Return(Expr<'a>),
    Call(Call<'a>),
    Let(Let<'a>),
    Assign(Assign<'a>),
}

impl<'a> From<Assign<'a>> for Statement<'a> {
    fn from(v: Assign<'a>) -> Self {
        Self::Assign(v)
    }
}

impl<'a> From<Let<'a>> for Statement<'a> {
    fn from(v: Let<'a>) -> Self {
        Self::Let(v)
    }
}

impl<'a> From<Call<'a>> for Statement<'a> {
    fn from(v: Call<'a>) -> Self {
        Self::Call(v)
    }
}

pub struct Call<'a> {
    pub name: &'a str,
    pub args: Vec<Expr<'a>>,
}

#[derive(Clone, Copy)]
pub enum BinOp {
    Add,
    Mul,
    Div,
    Sub,
}

pub struct Binary<'a> {
    pub left: Expr<'a>,
    pub op: BinOp,
    pub right: Expr<'a>,
}

pub enum Expr<'a> {
    Literal(Literal<'a>),
    Call(Call<'a>),
    Var(&'a str),
    Binary(Box<Binary<'a>>),
}

impl<'a> From<Binary<'a>> for Expr<'a> {
    fn from(v: Binary<'a>) -> Self {
        Self::Binary(Box::new(v))
    }
}

impl<'a> From<Call<'a>> for Expr<'a> {
    fn from(v: Call<'a>) -> Self {
        Self::Call(v)
    }
}

impl<'a> From<Literal<'a>> for Expr<'a> {
    fn from(v: Literal<'a>) -> Self {
        Self::Literal(v)
    }
}

pub enum Literal<'a> {
    Int(u64),
    RawStr(&'a str),
}

impl<'a> From<u64> for Literal<'a> {
    fn from(v: u64) -> Self {
        Self::Int(v)
    }
}
