const std = @import("std");

const okc = @import("okc");

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

    pub const Array = @import("typ/Array.zig");
    pub const Fun = @import("typ/Fun.zig");
    pub const Lazy = @import("typ/Lazy.zig");
    pub const LLPrinter = @import("typ/LLPrinter.zig");
    pub const Name = @import("typ/Name.zig");
    pub const Prime = @import("typ/prime.zig").Prime;
    pub const Ptr = @import("typ/Ptr.zig");
    pub const Slice = @import("typ/Slice.zig");

    pub var memo: okc.Memo(@This()) = undefined;

    pub fn getStructName(norm: Typ, location: okc.Location, failer: *okc.Failer) ?Typ.Name {
        switch (norm) {
            .err => return null,
            .name => |name| return name,
            .loc_name => |located| return located.bare,
            .slice, .array, .any, .lazy, .int => {
                std.log.err("getTypName: {f}", .{norm});
                unreachable;
            },
            .fun, .prime, .ptr => {
                failer.notStruct(location, norm);
                return null;
            },
        }
    }

    pub fn solve(self: @This(), arena: std.mem.Allocator) error{OutOfMemory}!@This() {
        if (self == .lazy) {
            return self.lazy.typ.solve(arena);
        }
        return self.updateRec(solve, .{arena}, arena);
    }

    pub fn getFun(self: @This(), location: okc.Location, failer: *okc.Failer) ?Typ.Fun {
        switch (self.normalise()) {
            .fun => |fun| return fun,
            .err => return null,
            else => {
                failer.fail(location, "value of type `{f}` is not a function", .{self});
                return null;
            },
        }
    }

    pub fn check(
        self: @This(),
        ctx: Check,
    ) error{OutOfMemory}!@This() {
        if (self == .name) {
            return self;
        }
        const res = try self.updateRec(check, .{ctx}, ctx.arena);
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

    pub fn resolve(self: @This(), map: std.StringHashMap(@This()), arena: std.mem.Allocator) error{OutOfMemory}!@This() {
        if (self.getName()) |name| {
            if (map.get(name.name)) |resolved| {
                return resolved;
            }
        }
        return self.updateRec(resolve, .{ map, arena }, arena);
    }

    pub fn fromName(name: []const u8, location: okc.Location) @This() {
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

    pub fn unify(a: Typ, b: Typ, location: okc.Location, failer: *okc.Failer) Typ {
        if (a.unifyOrNull(b, .active)) |typ| {
            if (Typ.debug_unify) {
                std.log.debug("==> {f}", .{typ});
            }
            return typ;
        }
        failer.wrongTyp(location, a, b);
        if (a == .ptr and
            a.ptr.typ.* == .prime and
            a.ptr.typ.prime == .u8 and
            b == .slice and
            b.slice.typ.* == .prime and
            b.slice.typ.prime == .u8)
        {
            std.log.info("append `.ptr` to get C-style string\n", .{});
        }
        return .err;
    }

    pub fn unifyOrNull(a: @This(), b: @This(), mode: UnifyMode) ?@This() {
        std.log.debug("unify {f} vs {f}", .{ a, b });
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
                const typ = aroot.typ.unifyOrNull(broot.typ.*, mode) orelse return null;
                aroot.set(typ);
                broot.set(.{ .lazy = aroot });
            }
            return .{ .lazy = aroot };
        }
        if (a == .lazy) {
            const res = a.lazy.typ.unifyOrNull(b, mode) orelse return null;
            if (mode == .active) {
                a.lazy.set(res);
            }
            return a;
        }
        if (b == .lazy) {
            const res = a.unifyOrNull(b.lazy.typ.*, mode) orelse return null;
            if (mode == .active) {
                b.lazy.set(res);
            }
            return b;
        }
        if (a == .slice and b == .ptr and b.ptr.typ.* == .array and
            a.slice.mutable == b.ptr.mutable)
        {
            if (a.slice.typ != b.ptr.typ.array.typ and
                a.slice.typ.unifyOrNull(b.ptr.typ.array.typ.*, mode) == null)
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
                _ = ag.unifyOrNull(bg, mode) orelse return null;
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
                    _ = fun.ret_typ.unifyOrNull(b.fun.ret_typ.*, mode) orelse return null;
                }
                for (fun.params, b.fun.params) |ap, bp| {
                    _ = ap.unifyOrNull(bp, mode) orelse return null;
                }
                return a;
            },
            .slice => |aslice| {
                if (aslice.mutable != b.slice.mutable) {
                    return null;
                }
                if (aslice.typ != b.slice.typ) {
                    _ = aslice.typ.unifyOrNull(b.slice.typ.*, mode) orelse return null;
                }
                return a;
            },
            .ptr => |aptr| {
                if (aptr.mutable and !b.ptr.mutable) {
                    return null;
                }
                if (aptr.typ != b.ptr.typ and aptr.typ.unifyOrNull(b.ptr.typ.*, mode) == null) {
                    return null;
                }
                return a;
            },
            .array => |arr| {
                if (arr.len != b.array.len or
                    (arr.typ != b.array.typ and arr.typ.unifyOrNull(b.array.typ.*, mode) == null))
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

    fn updateRec(self: @This(), fun: anytype, args: anytype, arena: std.mem.Allocator) !@This() {
        switch (self) {
            .array => |array| {
                const new = try @call(.auto, fun, .{array.typ.*} ++ args);
                return .{ .array = .{
                    .typ = try memo.box(new, arena),
                    .len = array.len,
                } };
            },
            .fun => |fun_typ| {
                const params = try arena.alloc(Typ, fun_typ.params.len);
                defer arena.free(params);
                for (params, fun_typ.params) |*target, param| {
                    target.* = try @call(.auto, fun, .{param} ++ args);
                }
                const new = try @call(.auto, fun, .{fun_typ.ret_typ.*} ++ args);
                return .{ .fun = .{
                    .params = try memo.save(params, arena),
                    .ret_typ = try memo.box(new, arena),
                } };
            },
            .name => |name| return .{ .name = try name.updateGenerics(fun, args, arena) },
            .loc_name => |located| return .{ .loc_name = .{
                .location = located.location,
                .bare = try located.bare.updateGenerics(fun, args, arena),
            } },
            .ptr => |ptr| {
                const new = try @call(.auto, fun, .{ptr.typ.*} ++ args);
                return .{ .ptr = .{
                    .typ = try memo.box(new, arena),
                    .mutable = ptr.mutable,
                } };
            },
            .slice => |slice| {
                const new = try @call(.auto, fun, .{slice.typ.*} ++ args);
                return .{ .slice = .{
                    .typ = try memo.box(new, arena),
                    .mutable = false,
                } };
            },
            .any, .err, .prime, .int, .lazy => return self,
        }
    }

    pub fn isVoid(self: @This()) bool {
        return self == .prime and self.prime == .void;
    }

    pub const Check = struct {
        arena: std.mem.Allocator,
        items: std.StringHashMap(okc.Item.Info),
        generics_checker: *okc.Item.Generic.Checker,
        failer: *okc.Failer,
    };
};
