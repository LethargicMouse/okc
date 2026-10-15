const std = @import("std");

const Failer = @import("../Failer.zig");
const Item = @import("../Item.zig");
const Location = @import("../Location.zig");
const Memo = @import("../memo.zig").Memo;
const Module = @import("../Module.zig");

pub const Typ = union(enum) {
    any,
    array: Array,
    err,
    fun: Fun,
    int,
    lazy: Lazy,
    loc_name: Name.Located,
    name: Name,
    prime: Prime,
    ptr: Ptr,
    slice: Slice,

    pub const Array = @import("Array.zig");
    pub const Fun = @import("Fun.zig");
    pub const Lazy = @import("Lazy.zig");
    pub const Name = @import("Name.zig");
    pub const Ptr = @import("Ptr.zig");
    pub const Slice = @import("Slice.zig");

    pub var memo: Memo(@This()) = undefined;

    pub fn check(
        self: @This(),
        ctx: Check,
    ) error{OutOfMemory}!@This() {
        if (self == .name) {
            return self;
        }
        const res = try self.updateRec(check, .{ctx});
        if (res == .loc_name) {
            if (ctx.generics_checker.mark(res.loc_name.bare.name)) {
                return res;
            }
            const maybe_resolved = res.loc_name.checkDecl(ctx.items, ctx.failer) catch |err| switch (err) {
                error.BadType => return .err,
            };
            if (maybe_resolved) |resolved| {
                return resolved;
            }
        }
        return res;
    }

    pub fn getName(self: @This()) ?Name {
        return switch (self) {
            .name => |name| name,
            .loc_name => |located| located.bare,
            else => null,
        };
    }

    pub fn solve(self: @This()) error{OutOfMemory}!@This() {
        if (self == .lazy) {
            return self.lazy.typ.solve();
        }
        return self.updateRec(solve, .{});
    }

    pub fn resolve(self: @This(), map: std.StringHashMap(@This())) error{OutOfMemory}!@This() {
        if (self.getName()) |name| {
            if (map.get(name.name)) |resolved| {
                return resolved;
            }
        }
        return self.updateRec(resolve, .{map});
    }

    pub fn fromName(name: []const u8, location: Location) @This() {
        if (std.meta.stringToEnum(Prime, name)) |prime| {
            return .{ .prime = prime };
        }
        return .{ .loc_name = .{
            .bare = .{ .name = name },
            .location = location,
        } };
    }

    pub fn eql(a: @This(), b: @This()) bool {
        if (@backingInt(a) != @backingInt(b)) {
            return false;
        }
        return switch (a) {
            .loc_name => |located| located.location.eql(b.loc_name.location),
            .prime => |aprime| aprime == b.prime,
            .name => |aname| aname.eql(b.name),
            .fun => |afun| afun.eql(b.fun),
            .slice => |aslice| aslice.eql(b.slice),
            .ptr => |aptr| aptr.eql(b.ptr),
            .array => |arr| arr.eql(b.array),
            .lazy => |alazy| alazy.typ == b.lazy.typ,
            .any, .err, .int => true,
        };
    }

    pub fn hashIn(self: @This(), hasher: *std.hash.Wyhash) void {
        hasher.update(&.{@backingInt(self)});
        switch (self) {
            .loc_name => |located| located.location.hashIn(hasher),
            .prime => |prime| prime.hashIn(hasher),
            .name => |name| name.hashIn(hasher),
            .fun => |fun| fun.hashIn(hasher),
            .ptr => |ptr| ptr.hashIn(hasher),
            .array => |array| array.hashIn(hasher),
            .lazy => |inner| hasher.update(std.mem.asBytes(&inner)),
            .slice => |slice| slice.hashIn(hasher),
            .any, .err, .int => {},
        }
    }

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (self) {
            .prime => |prime| try prime.format(writer),
            .loc_name => |located| try located.bare.format(writer),
            .name => |name| try name.format(writer),
            .fun => |fun| try fun.format(writer),
            .ptr => |ptr| try ptr.format(writer),
            .array => |array| try array.format(writer),
            .slice => |slice| try slice.format(writer),
            .lazy => |lazy| try lazy.format(writer),
            .err => try writer.writeAll("<err>"),
            .any => try writer.writeAll("_"),
            .int => try writer.writeAll("<int>"),
        }
    }

    pub fn isNumber(self: @This()) bool {
        switch (self) {
            .prime => |prime| return prime.isNumber(),
            .err, .int => return true,
            .lazy => |lazy| return lazy.typ.isNumber(),
            else => return false,
        }
    }

    pub fn normalise(self: @This()) @This() {
        var res = self;
        if (res == .lazy) {
            res.lazy = res.lazy.shorten();
        }
        // may be 2 or 1 lazies on the way
        while (res == .lazy) {
            res = res.lazy.typ.*;
        }
        return res;
    }

    pub const debug_unify = false;

    pub fn unify(a: @This(), b: @This(), mode: UnifyMode) ?@This() {
        if (debug_unify) {
            std.log.debug("unify {f} vs {f}\n", .{ a, b });
        }
        if (a.eql(b)) {
            return a;
        }
        if (a == .err or b == .err) {
            return .err;
        }
        if (a == .any) {
            return b;
        }
        if (b == .any) {
            return a;
        }
        if (a == .lazy and b == .lazy) {
            const aroot = a.lazy.shorten();
            const broot = b.lazy.shorten();
            if (aroot.typ != broot.typ) {
                const typ = aroot.typ.unify(broot.typ.*, mode) orelse return null;
                aroot.set(typ);
                broot.set(.{ .lazy = aroot });
            }
            return .{ .lazy = aroot };
        }
        if (a == .lazy) {
            const res = a.lazy.typ.unify(b, mode) orelse return null;
            if (mode == .active) {
                a.lazy.set(res);
            }
            return a;
        }
        if (b == .lazy) {
            const res = a.unify(b.lazy.typ.*, mode) orelse return null;
            if (mode == .active) {
                b.lazy.set(res);
            }
            return b;
        }
        if (a == .slice and b == .ptr and b.ptr.typ.* == .array and
            a.slice.mutable == b.ptr.mutable)
        {
            if (a.slice.typ != b.ptr.typ.array.typ and
                a.slice.typ.unify(b.ptr.typ.array.typ.*, mode) == null)
            {
                return null;
            }
            return a;
        }
        if (a == .int and b.isNumber()) {
            return b;
        }
        if (b == .int and a.isNumber()) {
            return a;
        }
        if (a.getName()) |aname| {
            const bname = b.getName() orelse return null;
            if (!std.mem.eql(u8, aname.name, bname.name)) {
                return null;
            }
            for (aname.generics, bname.generics) |ag, bg| {
                _ = ag.unify(bg, mode) orelse return null;
            }
            return b;
        }
        if (@backingInt(a) != @backingInt(b)) {
            return null;
        }
        switch (a) {
            .prime => |aprime| if (aprime == b.prime) {
                return b;
            } else {
                return null;
            },
            .fun => |fun| {
                if (fun.ret_typ != b.fun.ret_typ) {
                    _ = fun.ret_typ.unify(b.fun.ret_typ.*, mode) orelse return null;
                }
                for (fun.params, b.fun.params) |ap, bp| {
                    _ = ap.unify(bp, mode) orelse return null;
                }
                return a;
            },
            .slice => |aslice| {
                if (aslice.mutable != b.slice.mutable) {
                    return null;
                }
                if (aslice.typ != b.slice.typ) {
                    _ = aslice.typ.unify(b.slice.typ.*, mode) orelse return null;
                }
                return a;
            },
            .ptr => |aptr| {
                if (aptr.mutable and !b.ptr.mutable) {
                    return null;
                }
                if (aptr.typ != b.ptr.typ and aptr.typ.unify(b.ptr.typ.*, mode) == null) {
                    return null;
                }
                return a;
            },
            .array => |arr| {
                if (arr.len != b.array.len or
                    (arr.typ != b.array.typ and arr.typ.unify(b.array.typ.*, mode) == null))
                {
                    return null;
                }
                return a;
            },
            .lazy, .any, .err, .int, .loc_name, .name => unreachable,
        }
    }

    pub const UnifyMode = enum {
        active,
        passive,
    };

    fn updateRec(self: @This(), fun: anytype, args: anytype) !@This() {
        switch (self) {
            .array => |array| {
                const new = try @call(.auto, fun, .{array.typ.*} ++ args);
                return .{ .array = .{
                    .typ = try memo.box(new),
                    .len = array.len,
                } };
            },
            .fun => |fun_typ| {
                const params = try Module.arena.alloc(Typ, fun_typ.params.len);
                defer Module.arena.free(params);
                for (params, fun_typ.params) |*target, param| {
                    target.* = try @call(.auto, fun, .{param} ++ args);
                }
                const new = try @call(.auto, fun, .{fun_typ.ret_typ.*} ++ args);
                return .{ .fun = .{
                    .params = try memo.save(params),
                    .ret_typ = try memo.box(new),
                } };
            },
            .name => |name| return .{ .name = try name.updateGenerics(fun, args) },
            .loc_name => |located| return .{ .loc_name = .{
                .location = located.location,
                .bare = try located.bare.updateGenerics(fun, args),
            } },
            .ptr => |ptr| {
                const new = try @call(.auto, fun, .{ptr.typ.*} ++ args);
                return .{ .ptr = .{
                    .typ = try memo.box(new),
                    .mutable = ptr.mutable,
                } };
            },
            .slice => |slice| {
                const new = try @call(.auto, fun, .{slice.typ.*} ++ args);
                return .{ .slice = .{
                    .typ = try memo.box(new),
                    .mutable = false,
                } };
            },
            .any, .err, .prime, .int, .lazy => return self,
        }
    }

    pub fn isVoid(self: @This()) bool {
        return self == .prime and self.prime == .void;
    }

    pub const Prime = enum {
        bool,
        i32,
        u32,
        u64,
        u8, // zlinter-disable-current-line field_naming
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
            hasher.update(&.{@backingInt(prime)});
        }
    };

    pub const Check = struct {
        items: std.StringHashMap(Item.Info),
        generics_checker: *Item.Generic.Checker,
        failer: *Failer,
    };

    pub const SolveReq = struct {
        location: ?Location,
        typ: *Typ,
    };
};
