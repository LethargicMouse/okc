const std = @import("std");

const Typ = @import("mod.zig").Typ;

typ: *Typ,

pub fn new(arena: *std.heap.ArenaAllocator, typ: Typ) !@This() {
    const ptr = try arena.allocator().create(Typ);
    ptr.* = typ;
    return .{ .typ = ptr };
}

pub fn shorten(self: @This()) @This() {
    if (self.typ.* == .lazy) {
        self.typ.lazy = self.typ.lazy.shorten();
        if (debug) {
            std.log.debug("=> {f}\n", .{self});
        }
        return self.typ.lazy;
    } else {
        return self;
    }
}

const debug = false;

pub fn set(self: @This(), typ: Typ) void {
    self.typ.* = typ;
    if (debug) {
        std.log.debug("=> {f}\n", .{Typ{ .lazy = self }});
    }
}

pub fn format(self: @This(), writer: *std.Io.Writer) !void {
    if (debug) {
        try writer.print("@{x}<{f}>", .{ @intFromPtr(self.typ) & 0xffff, self });
    } else {
        try self.typ.format(writer);
    }
}

pub fn makeGenerics(gpa: std.mem.Allocator, fun_arena: *std.heap.ArenaAllocator, len: usize) ![]Typ {
    const res = try gpa.alloc(Typ, len);
    for (res) |*target| {
        target.* = .{ .lazy = try new(fun_arena, .any) };
    }
    return res;
}
