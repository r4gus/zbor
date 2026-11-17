/// Old zbor API
///
/// Deprecated
pub const v0 = @import("v0.zig");

pub const DataItem = @import("DataItem.zig");

const tests = @import("tests.zig");

test "main tests" {
    _ = v0;
    _ = DataItem;
    _ = tests;
}
