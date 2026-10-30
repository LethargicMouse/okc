const std = @import("std");

const okc = @import("okc");

pub const Kind = union(enum) {
    array: okc.Expr.Array,
    binary: *okc.Expr.Binary,
    bool: bool,
    call: *okc.Expr.Call,
    char: u8,
    deref: *okc.Expr.Deref,
    elem: *okc.Expr.Elem,
    field: *okc.Expr.Field,
    i_array: okc.Expr.Array.Indexed,
    int: okc.Expr.Int,
    member: okc.Expr.Member,
    method: *okc.Expr.Method,
    named_struc: okc.Expr.Struct.Named,
    neg: *okc.Expr.Neg,
    notb: *okc.Expr.Notb,
    ptr: *okc.Expr.Ptr,
    sizeof: okc.Expr.Sizeof,
    str: okc.Expr.Str,
    struc: okc.Expr.Struct,
    subslice: *okc.Expr.Subslice,
    undef: okc.Expr.Undef,
    vari: okc.Expr.Var,

    pub fn makeUnary(unary: okc.Expr.Unary, expr: okc.Expr, arena: std.mem.Allocator) !@This() {
        switch (unary) {
            .deref => {
                const deref = try arena.create(okc.Expr.Deref);
                deref.* = .{ .expr = expr };
                return .{ .deref = deref };
            },
            .neg => {
                const neg = try arena.create(okc.Expr.Neg);
                neg.* = .{ .expr = expr };
                return .{ .neg = neg };
            },
            .ptr => {
                const ptr = try arena.create(okc.Expr.Ptr);
                ptr.* = .{ .expr = expr };
                return .{ .ptr = ptr };
            },
            .notb => {
                const notb = try arena.create(okc.Expr.Notb);
                notb.* = .{ .expr = expr };
                return .{ .notb = notb };
            },
        }
    }
};
