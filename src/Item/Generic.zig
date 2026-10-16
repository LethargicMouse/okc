const std = @import("std");

const okc = @import("okc");

name: []const u8,
location: okc.Location,

pub const Checker = struct {
    generics: []const okc.Item.Generic,
    usage: std.bit_set.Dynamic,

    pub fn init(gpa: std.mem.Allocator, generics: []const okc.Item.Generic) !@This() {
        return .{
            .generics = generics,
            .usage = try .initEmpty(gpa, generics.len),
        };
    }

    pub fn deinit(self: *@This(), gpa: std.mem.Allocator) void {
        self.usage.deinit(gpa);
        self.* = undefined;
    }

    pub fn mark(self: *@This(), name: []const u8) bool {
        for (self.generics, 0..) |generic, i| {
            if (std.mem.eql(u8, generic.name, name)) {
                self.usage.set(i);
                return true;
            }
        }
        return false;
    }

    pub fn checkUsage(self: *@This(), failer: *okc.Failer) void {
        for (self.generics, 0..) |generic, i| {
            if (!self.usage.isSet(i)) {
                failer.unused(generic.location, generic.name);
            }
        }
    }
};
