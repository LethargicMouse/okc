const okc = @import("okc");

kind: Kind,
location: okc.Location,

const Kind = union(enum) {
    call: okc.Expr.Call.Postfix,
    elem: okc.Expr,
    field: okc.Expr.Var,
    method: Method,
    subslice: Subslice,
};

const Method = struct {
    vari: okc.Expr.Var,
    args: []okc.Expr,
    name_location: okc.Location,
};

const Subslice = struct {
    start: okc.Expr,
    end: okc.Expr,
};
