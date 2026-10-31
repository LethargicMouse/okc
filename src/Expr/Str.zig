const std = @import("std");

const okc = @import("okc");

bare: []const u8,

pub fn genDecl(self: @This(), ctx: *okc.Codegen) !okc.Expr.Str.GenInfo {
    const unescaped = try self.unescape(ctx.gpa);
    defer ctx.gpa.free(unescaped.repr);
    const tmp = ctx.counter.next();
    try ctx.writer.interface.print("\n@.s{} = private unnamed_addr constant [{} x i8] c\"{s}\\00\", align 1", .{
        tmp,
        unescaped.len + 1,
        unescaped.repr,
    });
    return .{
        .len = unescaped.len,
        .tmp = tmp,
    };
}

fn unescape(self: @This(), gpa: std.mem.Allocator) !Unescaped {
    var vec = try std.ArrayList(u8).initCapacity(gpa, self.bare.len);
    var i: usize = 0;
    var len = self.bare.len;
    while (i < self.bare.len) : (i += 1) {
        if (self.bare[i] == '\\') {
            i += 1;
            len -= 1;
            switch (self.bare[i]) {
                'n' => try vec.appendSlice(gpa, "\\0A"),
                'x' => {
                    try vec.append(gpa, '\\');
                    try vec.appendSlice(gpa, self.bare[i + 1 .. i + 3]);
                    i += 2;
                    len -= 2;
                },
                else => {
                    std.log.err("bad escape symbol: `\\{c}`", .{self.bare[i]});
                    // supposed to be checked by `Checker`
                    unreachable;
                },
            }
        } else {
            try vec.append(gpa, self.bare[i]);
        }
    }
    const repr = try vec.toOwnedSlice(gpa);
    return .{
        .len = len,
        .repr = repr,
    };
}

pub fn gen(self: @This(), ctx: *okc.Codegen) !okc.Val.Typed {
    const info = try self.genDecl(ctx);
    const ptr_u8 = try okc.Typ.memo.box(.{ .prime = .u8 }, ctx.arena);
    var res = okc.Val.Typed{
        .typ = .{ .slice = .{
            .typ = ptr_u8,
            .sized = true,
            .mutable = false,
        } },
        .bare = .undef,
    };
    try res.genIV(.{
        .typ = .{ .ptr = .{
            .typ = ptr_u8,
            .mutable = false,
        } },
        .bare = .{ .str = info.tmp },
    }, 0, ctx);
    try res.genIV(.{
        .typ = .{ .prime = .u64 },
        .bare = .{ .int = info.len },
    }, 1, ctx);
    return res;
}

pub fn genConst(self: @This(), ctx: *okc.Codegen) !okc.Typ {
    const info = try self.genDecl(ctx);
    try ctx.buffer.print(
        ctx.gpa,
        "%\"[]\" {{ ptr @.s{d}, i64 {d} }}",
        .{ info.tmp, info.len },
    );
    return .{ .slice = .{
        .typ = try okc.Typ.memo.box(.{ .prime = .u8 }, ctx.arena),
        .sized = true,
        .mutable = false,
    } };
}

pub fn check(arena: std.mem.Allocator) !okc.Expr.Info {
    const ptr = try okc.Typ.memo.box(.{ .prime = .u8 }, arena);
    return .{
        .typ = .{ .slice = .{
            .typ = ptr,
            .sized = true,
            .mutable = false,
        } },
        .mutable = false,
    };
}

pub const GenInfo = struct {
    len: usize,
    tmp: u32,
};

pub const Unescaped = struct {
    len: usize,
    repr: []const u8,
};
