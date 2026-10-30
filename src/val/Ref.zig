const std = @import("std");

const okc = @import("okc");

val: okc.Val,
inner_typ: okc.Typ,

pub fn genElem(self: @This(), index: okc.Val.Typed, ctx: *okc.Codegen) !@This() {
    switch (self.inner_typ) {
        .array => {
            const tmp = try self.genGEPIB(index, ctx);
            return .{
                .inner_typ = self.inner_typ.array.typ.*,
                .val = .{ .tmp = tmp },
            };
        },
        .slice => |slice| {
            const ptrptr = try self.genGEPIB(.int(0), ctx);
            const ptrref: okc.Val.Ref = .{
                .inner_typ = .{ .ptr = .{
                    .typ = slice.typ,
                    .mutable = false,
                } },
                .val = .{ .tmp = ptrptr },
            };
            const ptr = try ptrref.load(ctx);
            const tmp = ctx.newTmp();
            try ctx.buffer.?.print(
                ctx.gpa,
                "\n  %t{} = getelementptr {f}, ptr %t{}, {f}",
                .{ tmp, okc.Typ.LLPrinter{ .typ = slice.typ.* }, ptr, index },
            );
            return .{
                .inner_typ = slice.typ.*,
                .val = .{ .tmp = tmp },
            };
        },
        else => unreachable,
    }
}

pub fn genGEPIB(self: @This(), index: okc.Val.Typed, ctx: *okc.Codegen) !u32 {
    const tmp = ctx.counter.next();
    try ctx.buffer.?.print(
        ctx.gpa,
        "\n  %t{} = getelementptr inbounds {f}, ptr {f}, i32 0, {f}",
        .{ tmp, okc.Typ.LLPrinter{ .typ = self.inner_typ }, self.val, index },
    );
    return tmp;
}

pub fn loadTag(self: @This(), ctx: *okc.Codegen) !u32 {
    const tag_ptr = try self.genGEPIB(.int(0), ctx);
    const tag_ref: okc.Val.Ref = .{
        .inner_typ = .{ .prime = .i32 },
        .val = .{ .tmp = tag_ptr },
    };
    return tag_ref.load(ctx);
}

pub fn load(self: @This(), ctx: *okc.Codegen) !u32 {
    const res = ctx.counter.next();
    try ctx.buffer.?.print(
        ctx.gpa,
        "\n  %t{} = load {f}, ptr {f}",
        .{ res, okc.Typ.LLPrinter{ .typ = self.inner_typ }, self.val },
    );
    return res;
}

pub fn loadTypVal(self: @This(), ctx: *okc.Codegen) !okc.Val.Typed {
    const tmp = try self.load(ctx);
    return .{
        .typ = self.inner_typ,
        .bare = .{ .tmp = tmp },
    };
}

pub fn toPtrTypVal(self: @This(), arena: std.mem.Allocator) !okc.Val.Typed {
    return .{
        .typ = .{ .ptr = .{
            .typ = try okc.Typ.memo.box(self.inner_typ, arena),
            .mutable = false,
        } },
        .bare = self.val,
    };
}
