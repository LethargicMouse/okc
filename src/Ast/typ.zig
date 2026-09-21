const std = @import("std");

const Location = @import("../Location.zig");
const typ_kinds = @import("../typ_kinds.zig");
const Resolver = @import("../resolver.zig").Resolver(Typ);

pub const Typ = union(enum) {
    prime: Prime,
    name: Name,
    slice: Slice,
    ptr: Ptr,
    array: Array,
    fun: Fun,

    pub const Array = typ_kinds.Array(Typ);
    pub const Slice = typ_kinds.Slice(Typ);
    pub const Ptr = typ_kinds.Ptr(Typ);
    pub const Fun = typ_kinds.Fun(Typ);

    pub const Name = struct {
        name: []const u8,
        generics: []const Typ = &.{},
        location: Location = .fake,

        pub fn delocate(name: Name) typ_kinds.Name(Typ) {
            return .{
                .name = name.name,
                .generics = name.generics,
            };
        }

        pub fn resolve(name: Name, resolver: *Resolver) !Name {
            const resolved = try name.delocate().resolve(resolver);
            return .{
                .name = resolved.name,
                .generics = resolved.generics,
                .location = name.location,
            };
        }
    };

    pub const Prime = enum {
        u8,
        i32,
        u32,
        u64,
        bool,
        void,

        pub fn format(prime: Prime, writer: *std.Io.Writer) !void {
            try writer.writeAll(@tagName(prime));
        }

        pub fn isNumber(prime: Prime) bool {
            switch (prime) {
                .i32, .u8, .u32, .u64 => return true,
                .bool, .void => return false,
            }
        }

        pub fn hashIn(prime: Prime, hasher: *std.hash.Wyhash) void {
            hasher.update(&.{@intFromEnum(prime)});
        }
    };

    pub fn resolve(typ: Typ, resolver: *Resolver) error{OutOfMemory}!Typ {
        switch (typ) {
            .name => |name| if (resolver.map.get(name.name)) |resolved| {
                return resolved;
            } else {
                return .{ .name = try name.resolve(resolver) };
            },
            .fun => |fun| return .{ .fun = try fun.resolve(resolver) },
            .slice => |slice| return .{ .slice = try slice.resolve(resolver) },
            .ptr => |ptr| return .{ .ptr = try ptr.resolve(resolver) },
            .array => |array| return .{ .array = try array.resolve(resolver) },
            .prime => return typ,
        }
    }

    pub fn format(typ: Typ, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (typ) {
            .prime => |prime| try prime.format(writer),
            .name => |name| try name.delocate().format(writer),
            .slice => |slice| try slice.format(writer),
            .fun => |fun| try fun.format(writer),
            .ptr => |ptr| try ptr.format(writer),
            .array => |array| try array.format(writer),
        }
    }

    pub fn fromName(name: []const u8, location: Location) Typ {
        if (std.meta.stringToEnum(Prime, name)) |prime| {
            return .{ .prime = prime };
        }
        return .{ .name = .{
            .name = name,
            .location = location,
        } };
    }

    pub fn isVoid(typ: Typ) bool {
        return typ == .prime and typ.prime == .void;
    }

    pub fn eql(a: Typ, b: Typ) bool {
        if (@intFromEnum(a) != @intFromEnum(b)) {
            return false;
        }
        return switch (a) {
            .name => |aname| aname.delocate().eql(b.name.delocate()),
            .fun => |afun| afun.eql(b.fun),
            .prime => |aprime| aprime == b.prime,
            .slice => |aslice| aslice.eql(b.slice),
            .ptr => |aptr| aptr.eql(b.ptr),
            .array => |arr| arr.eql(b.array),
        };
    }

    pub fn hashIn(typ: Typ, hasher: *std.hash.Wyhash) void {
        hasher.update(&.{@intFromEnum(typ)});
        switch (typ) {
            .name => |name| name.delocate().hashIn(hasher),
            .ptr => |ptr| ptr.hashIn(hasher),
            .array => |array| array.hashIn(hasher),
            .slice => |slice| slice.hashIn(hasher),
            .prime => |prime| prime.hashIn(hasher),
            .fun => |fun| fun.hashIn(hasher),
        }
    }
};
