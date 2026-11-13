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
    maybe: Maybe,
    name: Name,
    never,
    prime: Prime,
    ptr: Ptr,
    slice: Slice,
    typ,

    pub const Array = @import("typ/Array.zig");
    pub const Fun = @import("typ/Fun.zig");
    pub const Lazy = @import("typ/Lazy.zig");
    pub const LLPrinter = @import("typ/LLPrinter.zig");
    pub const Maybe = @import("typ/Maybe.zig");
    pub const Name = @import("typ/Name.zig");
    pub const Prime = @import("typ/prime.zig").Prime;
    pub const Ptr = @import("typ/Ptr.zig");
    pub const Slice = @import("typ/Slice.zig");

    pub var memo: okc.Memo(@This()) = undefined;

    pub fn parseVerbal(ctx: *okc.Parser) error{ OutOfMemory, ParseFailed }!okc.Typ {
        const location = ctx.getLocation();
        const name = try ctx.parseName(.quiet);
        return okc.Typ.fromName(name, location);
    }

    pub fn getLayout(self: @This(), ctx: *okc.Codegen) !okc.Layout {
        std.log.debug("get layout of `{f}`", .{self});
        switch (self) {
            .prime => |prime| return prime.getLayout(),
            .array => |array| {
                const inner = try array.typ.getLayout(ctx);
                const cnt = try array.getLen(ctx);
                return .{
                    .size = inner.size * cnt,
                    .alig = inner.alig,
                };
            },
            .fun, .ptr => return .new(8, 8),
            .slice => return .new(16, 8),
            .name => |name| {
                try okc.Item.TypDecl.genNamed(name, ctx);
                return ctx.typ_decls.get(name).?.layout;
            },
            .loc_name => |name| {
                try okc.Item.TypDecl.genNamed(name.bare, ctx);
                return ctx.typ_decls.get(name.bare).?.layout;
            },
            else => unreachable,
        }
    }

    pub fn parse(ctx: *okc.Parser) error{ OutOfMemory, ParseFailed }!okc.Typ {
        return ctx.either(.{
            parseNever,
            Maybe.parseTyp,
            Fun.parseTyp,
            Name.parseGenericTyp,
            okc.Typ.parseVerbal,
            Ptr.parseTyp,
            Array.parseTyp,
            Slice.parseTyp,
        }) catch |err| {
            try ctx.fail("<type>");
            return err;
        };
    }

    fn parseNever(ctx: *okc.Parser) !okc.Typ {
        try ctx.expect(.bang, .quiet);
        return .never;
    }

    pub fn solve(self: @This(), gpa: std.mem.Allocator, arena: *std.heap.ArenaAllocator) error{OutOfMemory}!@This() {
        if (self == .lazy) {
            return self.lazy.typ.solve(gpa, arena);
        }
        return self.updateRec(solve, .{ gpa, arena }, gpa, arena);
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
        std.log.debug("check `{f}`", .{self});
        if (self == .name) {
            unreachable;
        }
        if (self == .loc_name) {
            const res = try updateRec(.{ .name = self.loc_name.bare }, check, .{ctx}, ctx.gpa, ctx.arena);
            if (okc.Item.TypDecl.checkTyped(.{
                .bare = res.name,
                .location = self.loc_name.location,
            }, ctx)) |resolved| {
                return resolved;
            }
            return res;
        }
        return self.updateRec(check, .{ctx}, ctx.gpa, ctx.arena);
    }

    pub fn resolve(self: @This(), ctx: Resolve) error{OutOfMemory}!@This() {
        if (self == .name) {
            if (ctx.map.get(self.name.name)) |resolved| {
                return resolved;
            }
        }
        return self.updateRec(resolve, .{ctx}, ctx.gpa, ctx.arena);
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
            .maybe => |amaybe| amaybe.eql(b.maybe),
            .any, .err, .int, .typ, .never => true,
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
            .maybe => |maybe| maybe.hashIn(hasher),
            .any, .err, .int, .typ, .never => {},
        }
    }

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (self) {
            .maybe => |maybe| try maybe.format(writer),
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
            .typ => try writer.writeAll("type"),
            .never => try writer.writeAll("!"),
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

    pub fn unify(b: Typ, a: Typ, location: okc.Location, failer: *okc.Failer) Typ {
        if (a.unifyOrNull(b, .active)) |typ| {
            std.log.debug("==> {f}", .{typ});
            return typ;
        }
        failer.wrongTyp(location, a, b);
        if (a == .slice and
            a.slice.typ.* == .prime and
            a.slice.typ.prime == .u8 and
            !a.slice.sized and
            b == .slice and
            b.slice.typ.* == .prime and
            b.slice.typ.prime == .u8 and
            b.slice.sized)
        {
            std.log.info("append `.ptr` to get C-style string\n", .{});
        } else if (a.isVoid()) {
            std.log.info("prepend `_ =` to ignore value\n", .{});
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
        if (b == .never) {
            return .never;
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
        if (a == .slice and b == .ptr) {
            const bnorm = b.ptr.typ.normalise();
            if (bnorm == .array and a.slice.mutable == b.ptr.mutable) {
                if (a.slice.typ != bnorm.array.typ and
                    a.slice.typ.unifyOrNull(bnorm.array.typ.*, mode) == null)
                {
                    return null;
                }
                return a;
            }
        }
        if (a == .int and b.isNumber()) {
            return b;
        }
        if (b == .int and a.isNumber()) {
            return a;
        }
        if (a == .name) {
            const bname = if (b == .name) b.name else return null;
            if (!std.mem.eql(u8, a.name.name, bname.name)) {
                return null;
            }
            for (a.name.generics, bname.generics) |ag, bg| {
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
                if (aslice.mutable and !b.slice.mutable or
                    aslice.sized != b.slice.sized)
                {
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
                if (!arr.index.eql(b.array.index) or
                    (arr.typ != b.array.typ and arr.typ.unifyOrNull(b.array.typ.*, mode) == null))
                {
                    return null;
                }
                return a;
            },
            .maybe => |amaybe| {
                if (amaybe.typ != b.maybe.typ and amaybe.typ.unifyOrNull(b.maybe.typ.*, mode) == null) {
                    return null;
                }
                return a;
            },
            .lazy, .any, .err, .int, .loc_name, .name, .typ, .never => unreachable,
        }
    }

    pub const UnifyMode = enum {
        active,
        passive,
    };

    fn updateRec(
        self: @This(),
        fun: anytype,
        args: anytype,
        gpa: std.mem.Allocator,
        arena: *std.heap.ArenaAllocator,
    ) !@This() {
        switch (self) {
            .array => |array| {
                const new = try @call(.auto, fun, .{array.typ.*} ++ args);
                return .{ .array = .{
                    .typ = try memo.box(new, arena),
                    .index = array.index,
                } };
            },
            .fun => |fun_typ| {
                const params = try gpa.alloc(Typ, fun_typ.params.len);
                defer gpa.free(params);
                for (params, fun_typ.params) |*target, param| {
                    target.* = try @call(.auto, fun, .{param} ++ args);
                }
                const new = try @call(.auto, fun, .{fun_typ.ret_typ.*} ++ args);
                return .{ .fun = .{
                    .params = try memo.save(params, arena),
                    .ret_typ = try memo.box(new, arena),
                    .context = fun_typ.context,
                } };
            },
            .name => |name| return .{ .name = try name.updateGenerics(fun, args, gpa, arena) },
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
                    .sized = slice.sized,
                    .mutable = slice.mutable,
                } };
            },
            .maybe => |maybe| {
                const new = try @call(.auto, fun, .{maybe.typ.*} ++ args);
                return .{ .maybe = .{ .typ = try memo.box(new, arena) } };
            },
            .loc_name => unreachable,
            .any, .err, .prime, .int, .lazy, .typ, .never => return self,
        }
    }

    pub fn isVoid(self: @This()) bool {
        return self == .prime and self.prime == .void;
    }

    pub const Check = struct {
        gpa: std.mem.Allocator,
        arena: *std.heap.ArenaAllocator,
        items: *std.StringHashMap(okc.Item.Info),
        modules: *std.StringHashMap(okc.Module.Info),
        failer: *okc.Failer,
        mod_name: []const u8,
    };

    pub const Resolve = struct {
        gpa: std.mem.Allocator,
        arena: *std.heap.ArenaAllocator,
        map: std.StringHashMap(Typ),
    };
};
