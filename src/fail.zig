const std = @import("std");

const Location = @import("Location.zig");
const Typ = @import("typ/typ.zig").Typ;

var errors_cnt: u16 = 0;

pub fn ensureNoErrors() error{Handled}!void {
    if (errors_cnt != 0) {
        std.log.err("compilation failed with {} errors", .{errors_cnt});
        return error.Handled;
    }
}

pub fn fail(location: Location, comptime msg: []const u8, args: anytype) void {
    std.log.err("in {f}\n     " ++ msg ++ "\n", .{location} ++ args);
    errors_cnt += 1;
}

pub fn unused(location: Location, name: []const u8) void {
    fail(location, "item `{s}` is never used", .{name});
}

pub fn alreadyDeclared(
    location: Location,
    name: []const u8,
    prev: Location,
) void {
    fail(
        location,
        "item `{s}` is already declared in {f}",
        .{ name, prev },
    );
}

pub fn notMut(location: Location) void {
    fail(location, "it is immutable", .{});
}

pub fn wrongTyp(location: Location, a: Typ, b: Typ) void {
    fail(location,
        \\wrong type:
        \\         expected  {f}
        \\            found  {f}
    , .{ a, b });
}

pub fn newFieldSecond(location: Location, name: []const u8) void {
    fail(location, "field `{s}` is already initialized", .{name});
}

pub fn notInit(location: Location, name: []const u8) void {
    fail(location, "field `{s}` is not initialized", .{name});
}

pub fn noField(
    location: Location,
    field: []const u8,
    typ: Typ,
) void {
    fail(location, "type `{f}` has no field named `{s}`", .{ typ, field });
}

pub fn notStruct(location: Location, typ: Typ) void {
    fail(location, "type `{f}` is not a struct", .{typ});
}

pub fn cannotInfer(typ: Typ, location: Location) void {
    fail(location, "cannot infer type", .{});
    if (typ != .any) {
        std.log.info("best guess is `{f}`\n", .{typ});
    }
}

pub fn notDeclared(location: Location, name: []const u8) void {
    fail(location, "item `{s}` is not declared", .{name});
}
