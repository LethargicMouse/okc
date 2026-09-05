const std = @import("std");

const Ast = @import("Ast.zig");
const HashContext = @import("hash_context.zig").HashContext;

pub const Resolver = struct {
    typs: *AstTyps,
    map: std.StringHashMap(Typ),

    pub fn resolve(resolver: *Resolver, typ: Typ) !Typ {
        switch (typ) {
            .name => |name| {
                if (resolver.map.get(name.name)) |resolved| {
                    return resolved;
                }
                const generics = try resolver.typs.arena.allocator().alloc(Typ, name.generics.len);
                for (generics, name.generics) |*target, generic| {
                    target.* = try resolver.resolve(generic);
                }
                return .{ .name = .{
                    .name = name.name,
                    .generics = generics,
                } };
            },
            .slice => |slice| {
                const new = try resolver.resolve(slice.typ.*);
                const ptr = try resolver.typs.box(new);
                return .{ .slice = .{
                    .typ = ptr,
                    .mutable = slice.mutable,
                } };
            },
            .ptr => |ptr| {
                const new = try resolver.resolve(ptr.typ.*);
                const new_ptr = try resolver.typs.box(new);
                return .{ .ptr = .{
                    .typ = new_ptr,
                    .mutable = ptr.mutable,
                } };
            },
            .array => |array| {
                const new = try resolver.resolve(array.typ.*);
                const new_ptr = try resolver.typs.box(new);
                return .{ .array = .{
                    .len = array.len,
                    .typ = new_ptr,
                } };
            },
            .prime => return typ,
        }
    }
};

pub const Typ = union(enum) {
    pub const Array = struct {
        len: []const u8,
        typ: *const Typ,
    };

    pub const Name = struct {
        name: []const u8,
        generics: []const Typ = &.{},

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

    prime: Prime,
    name: Name,
    slice: Slice,
    ptr: Ptr,
    array: Array,

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
            .ptr => |ptr| {
                try writer.writeAll("&");
                if (ptr.mutable) {
                    try writer.writeAll("mut ");
                }
                try ptr.typ.format(writer);
            },
            .array => |array| try writer.print("[{s}]{f}", .{ array.len, array.typ }),
        }
    }

    pub fn fromName(name: []const u8) Typ {
        if (std.meta.stringToEnum(Prime, name)) |prime| {
            return .{ .prime = prime };
        }
        return .{ .name = .{ .name = name } };
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
            .prime => |aprime| return aprime == b.prime,
            .slice => |aslice| return aslice.typ == b.slice.typ and
                aslice.mutable == b.slice.mutable,
            .ptr => |aptr| return aptr.typ == b.ptr.typ and
                aptr.mutable == b.ptr.mutable,
            .array => |arr| return arr.typ == b.array.typ and
                std.mem.eql(u8, arr.len, b.array.len),
        }
    }

    pub fn hashIn(typ: Typ, hasher: *std.hash.Wyhash) void {
        switch (typ) {
            .name => |name| {
                hasher.update(&.{0});
                hasher.update(name.name);
                for (name.generics) |generic| {
                    generic.hashIn(hasher);
                }
            },
            .ptr => |ptr| {
                hasher.update(&.{1});
                hasher.update(std.mem.asBytes(&ptr));
            },
            .array => |array| {
                hasher.update(&.{2});
                hasher.update(array.len);
                hasher.update(std.mem.asBytes(&array.typ));
            },
            .slice => |slice| {
                hasher.update(&.{3});
                hasher.update(std.mem.asBytes(&slice));
            },
            .prime => |prime| {
                hasher.update(&.{ 4, @intFromEnum(prime) });
            },
        }
    }
};

const Memo = std.HashMap(
    Typ,
    *const Typ,
    HashContext(Typ),
    std.hash_map.default_max_load_percentage,
);

const AstTyps = @This();

arena: std.heap.ArenaAllocator,
memo: Memo,

pub fn init(gpa: std.mem.Allocator) AstTyps {
    const arena = std.heap.ArenaAllocator.init(gpa);
    const memo = Memo.init(arena.child_allocator);
    return .{
        .arena = arena,
        .memo = memo,
    };
}

pub fn box(typs: *AstTyps, typ: Typ) !*const Typ {
    if (typs.memo.get(typ)) |res| {
        return res;
    }
    const res = try typs.arena.allocator().create(Typ);
    res.* = typ;
    try typs.memo.put(typ, res);
    return res;
}

pub fn deinit(typs: *AstTyps) void {
    typs.arena.deinit();
    typs.memo.deinit();
}

pub fn makeResolver(typs: *AstTyps, gpa: std.mem.Allocator) Resolver {
    return .{
        .typs = typs,
        .map = .init(gpa),
    };
}
