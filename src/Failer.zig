const std = @import("std");

const Location = @import("Location.zig");
const Typ = @import("typ.zig").Typ;

const Self = @This();
errors_cnt: u16 = 0,

pub fn init() Self {
    return .{};
}

pub fn ensureNoErrors(self: Self) error{Handled}!void {
    if (self.errors_cnt != 0) {
        std.log.err("check failed with {} errors", .{self.errors_cnt});
        return error.Handled;
    }
}

pub fn fail(self: *Self, location: Location, comptime msg: []const u8, args: anytype) void {
    std.log.err("in {f}\n     " ++ msg ++ "\n", .{location} ++ args);
    self.errors_cnt += 1;
}

pub fn unused(self: *Self, location: Location) void {
    self.fail(location, "item is never used", .{});
}

pub fn alreadyDeclared(
    self: *Self,
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

pub fn notMut(self: *Self, location: Location) void {
    self.fail(location, "it is immutable", .{});
}

pub fn wrongTyp(self: *Self, location: Location, a: Typ, b: Typ) void {
    self.fail(location,
        \\wrong type:
        \\         expected  {f}
        \\            found  {f}
    , .{ a, b });
}

pub fn newFieldSecond(self: *Self, location: Location, name: []const u8) void {
    self.fail(location, "field `{s}` is already initialized", .{name});
}

pub fn notInit(self: *Self, location: Location, name: []const u8) void {
    self.fail(location, "field `{s}` is not initialized", .{name});
}

pub fn noField(
    self: *Self,
    location: Location,
    field: []const u8,
    typ: Typ,
) void {
    self.fail(location, "type `{f}` has no field named `{s}`", .{ typ, field });
}

pub fn notStruct(self: *Self, location: Location, typ: Typ) void {
    self.fail(location, "type `{f}` is not a struct", .{typ});
}

pub fn cannotInfer(self: *Self, typ: Typ, location: Location) void {
    self.fail(location, "cannot infer type", .{});
    if (typ != .any) {
        std.log.info("best guess is `{f}`\n", .{typ});
    }
}

pub fn notDeclared(self: *Self, location: Location, name: []const u8) void {
    self.fail(location, "item `{s}` is not declared", .{name});
}
