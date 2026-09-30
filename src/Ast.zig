pub const Expr = @import("Ast/Expr.zig");
pub const Item = @import("Ast/Item.zig");
pub const Stmt = @import("Ast/Stmt.zig");
pub const Typ = @import("Ast/typ.zig").Typ;
const Location = @import("Location.zig");

const Ast = @This();

items: []Item,
location: Location,
