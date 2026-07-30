const std = @import("std");

pub const ExtFun = struct {
    header: Header,
};

pub const Header = struct {
    name: []const u8,
    params: []const Param,
    ret_typ: Typ,
};

pub const Param = struct {
    name: []const u8,
    typ: Typ,
};

pub const Typ = union(enum) {
    prime: Prime,
    name: []const u8,
    ptr: *Typ,

    pub fn fromName(name: []const u8) Typ {
        if (std.meta.stringToEnum(Prime, name)) |prime| {
            return .{ .prime = prime };
        }
        return .{ .name = name };
    }
};

pub const Prime = enum {
    u8,
    i32,
};

pub const Fun = struct {
    header: Header,
    statements: []const Statement,
};

pub const Statement = union(enum) {
    ret: Expr,
    call: Call,
};

pub const Call = struct {
    name: []const u8,
    args: []const Expr,
};

pub const Expr = union(enum) {
    int: []const u8,
    str: usize,
    call: Call,
};

const Ast = @This();

ext_funs: []const ExtFun,
funs: []const Fun,
strs: []const []const u8,
arena: std.heap.ArenaAllocator,

pub fn deinit(ast: Ast) void {
    ast.arena.deinit();
}
