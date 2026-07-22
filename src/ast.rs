pub struct Ast<'a> {
    pub structs: Vec<Struct<'a>>,
    pub ext_funs: Vec<ExtFun<'a>>,
    pub funs: Vec<Fun<'a>>,
}

pub struct Struct<'a> {
    pub name: &'a str,
    pub fields: Vec<FieldDecl<'a>>,
}

pub struct FieldDecl<'a> {
    pub name: &'a str,
    pub typ: Typ<'a>,
}

#[derive(Debug)]
pub struct ExtFun<'a> {
    pub header: Header<'a>,
}

#[derive(Debug)]
pub struct Fun<'a> {
    pub header: Header<'a>,
    pub body: Vec<Statement<'a>>,
}

#[derive(Debug)]
pub struct Header<'a> {
    pub name: &'a str,
    pub params: Vec<Param<'a>>,
}

#[derive(Debug)]
pub struct Param<'a> {
    pub name: &'a str,
    pub typ: Typ<'a>,
}

#[derive(Debug)]
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

#[derive(Debug)]
pub enum Prime {
    I32,
    U8,
}

#[derive(Debug)]
pub struct Let<'a> {
    pub name: &'a str,
    pub expr: Expr<'a>,
}

#[derive(Debug)]
pub struct Assign<'a> {
    pub name: &'a str,
    pub expr: Expr<'a>,
}

#[derive(Debug)]
pub struct If<'a> {
    pub condition: Expr<'a>,
    pub on_true: Vec<Statement<'a>>,
    pub on_false: Vec<Statement<'a>>,
}

pub type Block<'a> = Vec<Statement<'a>>;

#[derive(Debug)]
pub enum Statement<'a> {
    Return(Expr<'a>),
    Call(Call<'a>),
    Let(Let<'a>),
    Assign(Assign<'a>),
    If(If<'a>),
    Loop(Block<'a>),
    Break,
    Continue,
}

impl<'a> From<If<'a>> for Statement<'a> {
    fn from(v: If<'a>) -> Self {
        Self::If(v)
    }
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

#[derive(Debug)]
pub struct Call<'a> {
    pub name: &'a str,
    pub args: Vec<Expr<'a>>,
}

#[derive(Debug, Clone, Copy)]
pub enum BinOp {
    Add,
    Mul,
    Div,
    Sub,
    Equ,
    Rem,
}

#[derive(Debug)]
pub struct Binary<'a> {
    pub left: Expr<'a>,
    pub op: BinOp,
    pub right: Expr<'a>,
}

#[derive(Debug)]
pub struct Field<'a> {
    pub parent: Expr<'a>,
    pub name: &'a str,
}

#[derive(Debug)]
pub enum Expr<'a> {
    Literal(Literal<'a>),
    Call(Call<'a>),
    Var(&'a str),
    Binary(Box<Binary<'a>>),
    Field(Box<Field<'a>>),
}

impl<'a> From<Field<'a>> for Expr<'a> {
    fn from(v: Field<'a>) -> Self {
        Self::Field(Box::new(v))
    }
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

#[derive(Debug)]
pub enum Literal<'a> {
    Int(u64),
    RawStr(&'a str),
    Str(&'a str),
}

impl<'a> From<u64> for Literal<'a> {
    fn from(v: u64) -> Self {
        Self::Int(v)
    }
}
