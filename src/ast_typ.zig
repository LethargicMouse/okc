const std = @import("std");

const Ast = @import("Ast.zig");
const HashContext = @import("hash_context.zig").HashContext;
const Location = @import("Location.zig");
const Memo = @import("memo.zig").Memo;

pub const Typ = union(enum) {
    prime: Prime,
    name: Name,
    slice: Slice,
    ptr: Ptr,
    array: Array,
    fun: Fun,

    pub const Array = struct {
        len: u64,
        typ: *const Typ,
    };

    pub const Name = struct {
        name: []const u8,
        generics: []const Typ = &.{},
        location: Location = .fake,

        pub fn format(name: Name, writer: *std.Io.Writer) !void {
            try writer.print("{s}", .{name.name});
            if (name.generics.len != 0) {
                try writer.print("<{f}", .{name.generics[0]});
                for (name.generics[1..]) |generic| {
                    try writer.print(", {f}", .{generic});
                }
                try writer.writeByte('>');
            }
        }
    };

    pub const Slice = struct {
        typ: *const Typ,
        mutable: bool,
    };

    pub const Prime = enum {
        u8,
        i32,
        u32,
        u64,
        bool,
        void,

        pub fn isNumber(prime: Prime) bool {
            switch (prime) {
                .i32, .u8, .u32, .u64 => return true,
                .bool, .void => return false,
            }
        }
    };

    pub const Ptr = struct {
        typ: *const Typ,
        mutable: bool,
    };

    pub const Fun = struct {
        params: []const Typ,
        ret_typ: *const Typ,
    };

    pub const Resolver = struct {
        memo: *Memo(Typ),
        map: std.StringHashMap(Typ),

        pub fn init(gpa: std.mem.Allocator, memo: *Memo(Typ)) Resolver {
            return .{
                .memo = memo,
                .map = .init(gpa),
            };
        }

        pub fn resolve(resolver: *Resolver, typ: Typ) !Typ {
            switch (typ) {
                .name => |name| {
                    if (resolver.map.get(name.name)) |resolved| {
                        return resolved;
                    }
                    const generics = try resolver.memo.arena.allocator().alloc(Typ, name.generics.len);
                    for (generics, name.generics) |*target, generic| {
                        target.* = try resolver.resolve(generic);
                    }
                    return .{ .name = .{
                        .name = name.name,
                        .generics = generics,
                    } };
                },
                .fun => |fun| {
                    const params = try resolver.memo.arena.allocator().alloc(Typ, fun.params.len);
                    for (params, fun.params) |*target, param| {
                        target.* = try resolver.resolve(param);
                    }
                    const ret_typ = try resolver.resolve(fun.ret_typ.*);
                    const ptr = try resolver.memo.box(ret_typ);
                    return .{ .fun = .{
                        .params = params,
                        .ret_typ = ptr,
                    } };
                },
                .slice => |slice| {
                    const new = try resolver.resolve(slice.typ.*);
                    const ptr = try resolver.memo.box(new);
                    return .{ .slice = .{
                        .typ = ptr,
                        .mutable = slice.mutable,
                    } };
                },
                .ptr => |ptr| {
                    const new = try resolver.resolve(ptr.typ.*);
                    const new_ptr = try resolver.memo.box(new);
                    return .{ .ptr = .{
                        .typ = new_ptr,
                        .mutable = ptr.mutable,
                    } };
                },
                .array => |array| {
                    const new = try resolver.resolve(array.typ.*);
                    const new_ptr = try resolver.memo.box(new);
                    return .{ .array = .{
                        .len = array.len,
                        .typ = new_ptr,
                    } };
                },
                .prime => return typ,
            }
        }
    };

    pub fn format(typ: Typ, writer: *std.Io.Writer) !void {
        switch (typ) {
            .prime => |prime| try writer.writeAll(@tagName(prime)),
            .name => |name| try name.format(writer),
            .slice => |slice| {
                try writer.writeAll("[]");
                if (slice.mutable) {
                    try writer.writeAll("mut ");
                }
                try slice.typ.format(writer);
            },
            .fun => |fun| {
                try writer.writeAll("fn(");
                if (fun.params.len != 0) {
                    try fun.params[0].format(writer);
                    for (fun.params[1..]) |param| {
                        try writer.print(", {f}", .{param});
                    }
                }
                try writer.print(") {f}", .{fun.ret_typ});
            },
            .ptr => |ptr| {
                try writer.writeAll("&");
                if (ptr.mutable) {
                    try writer.writeAll("mut ");
                }
                try ptr.typ.format(writer);
            },
            .array => |array| try writer.print("[{}]{f}", .{ array.len, array.typ }),
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
        switch (a) {
            .name => |aname| {
                if (!std.mem.eql(u8, aname.name, b.name.name)) {
                    return false;
                }
                for (aname.generics, b.name.generics) |ag, bg| {
                    if (!ag.eql(bg)) {
                        return false;
                    }
                }
                return true;
            },
            .fun => |afun| {
                if (afun.ret_typ != b.fun.ret_typ) {
                    return false;
                }
                for (afun.params, b.fun.params) |ag, bg| {
                    if (!ag.eql(bg)) {
                        return false;
                    }
                }
                return true;
            },
            .prime => |aprime| return aprime == b.prime,
            .slice => |aslice| return aslice.typ == b.slice.typ and
                aslice.mutable == b.slice.mutable,
            .ptr => |aptr| return aptr.typ == b.ptr.typ and
                aptr.mutable == b.ptr.mutable,
            .array => |arr| return arr.typ == b.array.typ and
                arr.len == b.array.len,
        }
    }

    pub fn hashIn(typ: Typ, hasher: *std.hash.Wyhash) void {
        hasher.update(&.{@intFromEnum(typ)});
        switch (typ) {
            .name => |name| {
                hasher.update(name.name);
                for (name.generics) |generic| {
                    generic.hashIn(hasher);
                }
            },
            .ptr => |ptr| hasher.update(std.mem.asBytes(&ptr)),
            .array => |array| hasher.update(std.mem.asBytes(&array)),
            .slice => |slice| hasher.update(std.mem.asBytes(&slice)),
            .prime => |prime| hasher.update(&.{@intFromEnum(prime)}),
            .fun => |fun| {
                for (fun.params) |param| {
                    param.hashIn(hasher);
                }
                hasher.update(std.mem.asBytes(&fun.ret_typ));
            },
        }
    }
};
