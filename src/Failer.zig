const std = @import("std");

const Location = @import("Location.zig");
const Typ = @import("typ/mod.zig").Typ;

errors_cnt: u16 = 0,

pub fn init() @This() {
    return .{};
}

pub fn ensureNoErrors(self: @This()) error{Handled}!void {
    if (self.errors_cnt != 0) {
        std.log.err("check failed with {} errors", .{self.errors_cnt});
        return error.Handled;
    }
}

pub fn fail(self: *@This(), location: Location, comptime msg: []const u8, args: anytype) void {
    std.log.err("in {f}\n     " ++ msg ++ "\n", .{location} ++ args);
    self.errors_cnt += 1;
}

pub fn unused(self: *@This(), location: Location, name: []const u8) void {
    self.fail(location, "item `{s}` is never used", .{name});
}

pub fn alreadyDeclared(
    self: *@This(),
    location: Location,
    name: []const u8,
    prev: Location,
) void {
    self.fail(
        location,
        "item `{s}` is already declared in {f}",
        .{ name, prev },
    );
}

pub fn notMut(self: *@This(), location: Location) void {
    self.fail(location, "it is immutable", .{});
}

pub fn wrongTyp(self: *@This(), location: Location, a: Typ, b: Typ) void {
    self.fail(location,
        \\wrong type:
        \\         expected  {f}
        \\            found  {f}
    , .{ a, b });
}

pub fn newFieldSecond(self: *@This(), location: Location, name: []const u8) void {
    self.fail(location, "field `{s}` is already initialized", .{name});
}

pub fn notInit(self: *@This(), location: Location, name: []const u8) void {
    self.fail(location, "field `{s}` is not initialized", .{name});
}

pub fn noField(
    self: *@This(),
    location: Location,
    field: []const u8,
    typ: Typ,
) void {
    self.fail(location, "type `{f}` has no field named `{s}`", .{ typ, field });
}

pub fn notStruct(self: *@This(), location: Location, typ: Typ) void {
    self.fail(location, "type `{f}` is not a struct", .{typ});
}

pub fn cannotInfer(self: *@This(), typ: Typ, location: Location) void {
    self.fail(location, "cannot infer type", .{});
    if (typ != .any) {
        std.log.info("best guess is `{f}`\n", .{typ});
    }
}

pub fn notDeclared(self: *@This(), location: Location, name: []const u8) void {
    self.fail(location, "item `{s}` is not declared", .{name});
}
