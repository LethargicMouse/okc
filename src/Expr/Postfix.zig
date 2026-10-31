const okc = @import("okc");

kind: Kind,
location: okc.Location,

const Kind = union(enum) {
    call: okc.Expr.Call.Postfix,
    elem: okc.Expr,
    field: okc.Expr.Var,
    method: okc.Expr.Method.Postfix,
    subslice: okc.Expr.Subslice.Postfix,
};

pub fn parse(ctx: *okc.Parser) !okc.Expr.Postfix {
    return ctx.either(.{
        okc.Expr.Method.parsePostfix,
        okc.Expr.Call.parsePostfix,
        okc.Expr.Field.parsePostfix,
        okc.Expr.Subslice.parsePostfix,
        okc.Expr.Elem.parsePostfix,
    });
}
