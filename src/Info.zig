const std = @import("std");

const Ast = @import("Ast.zig");

pub const Typ = union(enum) {
    pub const Array = struct {
        len: []const u8,
        typ: Typ,
    };

    prime: Ast.Prime,
    name: []const u8,
    ptr: *const Typ,
    mut_ptr: *const Typ,
    array: *const Array,
    lazy: *Typ,
    int,
    any,
    err,

    pub fn format(typ: Typ, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (typ) {
            .prime => |prime| try writer.writeAll(@tagName(prime)),
            .name => |name| try writer.writeAll(name),
            .ptr => |inner| try writer.print("&{f}", .{inner}),
            .mut_ptr => |inner| try writer.print("&mut {f}", .{inner}),
            .array => |array| try writer.print(
                "[{s}]{f}",
                .{ array.len, array.typ },
            ),
            .lazy => |inner| try writer.print("@lazy<{f}>", .{inner}),
            .int => try writer.writeAll("<int>"),
            .err => try writer.writeAll("<err>"),
            .any => try writer.writeAll("<any>"),
        }
    }

    pub fn isNumber(typ: Typ) bool {
        switch (typ) {
            .prime => |prime| return prime.isNumber(),
            .int => return true,
            .err => return true,
            else => return false,
        }
    }

    pub fn normalise(typ: Typ) Typ {
        var res = typ;
        while (res == .lazy) {
            res = res.lazy.*;
        }
        return res;
    }
};

const Info = @This();

arena: std.heap.ArenaAllocator,
typs: []*const Typ,

pub fn init(gpa: std.mem.Allocator, ast_info: Ast.Info) !Info {
    var arena = std.heap.ArenaAllocator.init(gpa);
    const typs = try arena.allocator().alloc(*const Typ, ast_info.typ_ids);
    return .{
        .arena = arena,
        .typs = typs,
    };
}

pub fn deinit(info: *Info) void {
    info.arena.deinit();
}
