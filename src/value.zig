const QNAN: u64 = 0x7FF8_0000_0000_0000;
const SIGN_BIT: u64 = 0x8000_0000_0000_0000;
const TAG_BITS: u64 = 3;
const TAG_DISPLACER: u64 = 51 - TAG_BITS;
const PAYLOAD: u64 = (1 << (51 - TAG_BITS)) - 1;

const TAG_MASK: u64 = 0xFFFF_0000_0000_0000;
const INT_MASK: u64 = 0x0000_0000_FFFF_FFFF;

pub const Value = packed struct {
    raw: u64,

    const TAG_INT: u64 = 0x7FF9_0000_0000_0000;
    const TAG_TRUE: u64 = 0x7FFA_0000_0000_0000;
    const TAG_FALSE: u64 = 0x7FFB_0000_0000_000;

    const TAG_CLOSURE: u64 = 0xFFF9_0000_0000_0000;
    const TAG_PARTIAL: u64 = 0xFFFA_0000_0000_0000;
    const TAG_STRING: u64 = 0xFFFB_0000_0000_0000;

    pub const INT_ZERO: Value = Value{ .raw = TAG_INT };
    pub const INT_ONE: Value = Value{ .raw = TAG_INT | 1 };
    pub const TRUE: Value = Value{ .raw = TAG_TRUE };
    pub const FALSE: Value = Value{ .raw = TAG_FALSE };

    pub fn new(tag: u64, payload: u64) Value {
        return Value{ .raw = (QNAN | tag << TAG_DISPLACER | payload) };
    }

    pub fn new_closure(ptr: *Closure) Value {
        return Value{ .raw = TAG_CLOSURE | @intFromPtr(ptr) };
    }

    pub fn get_ptr(value: Value) *anyopaque {
        return @ptrFromInt(value.raw & PAYLOAD);
    }

    pub fn new_int(int: i32) Value {
        return Value{ .raw = TAG_INT | @as(u64, @as(u32, @bitCast(int))) };
    }

    pub fn from_f64(number: f64) Value {
        return Value{ .raw = @bitCast(number) };
    }

    pub fn get_f64(value: Value) f64 {
        return @bitCast(value.raw);
    }

    pub fn is_ptr(value: Value) bool {
        return value.raw & SIGN_BIT == SIGN_BIT;
    }

    pub fn is_int(value: Value) bool {
        return value.raw & TAG_MASK == TAG_INT;
    }

    pub fn get_int(value: Value) i32 {
        return @bitCast(@as(u32, @truncate(value.raw & INT_MASK)));
    }

    pub fn is_number(value: Value) bool {
        return value.raw & QNAN != QNAN;
    }

    pub fn is_closure(value: Value) bool {
        return (value.raw & TAG_MASK) == TAG_CLOSURE;
    }

    pub fn get_closure(value: Value) *Closure {
        return @ptrFromInt(value.raw & PAYLOAD);
    }
};

pub const Prototype = struct {
    arity: u8,
    locals: u16,
    prototypes: std.ArrayList(*Prototype),
    chunk: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) *Prototype {
        const proto = allocator.create(Prototype) catch @panic("Out of memory");
        proto.* = Prototype{
            .arity = 0,
            .locals = 0,
            .prototypes = std.ArrayList(*Prototype).init(allocator),
            .chunk = std.ArrayList(u8).init(allocator),
        };
        return proto;
    }

    pub fn deinit(self: *Prototype, allocator: std.mem.Allocator) void {
        for (self.prototypes.items) |item| {
            item.deinit(allocator);
        }
        self.prototypes.deinit();
        self.chunk.deinit();
        allocator.destroy(self);
    }
};

pub const Closure = struct {
    prototype: *Prototype,
};

pub const Partial = struct {
    arity: u8,
    applied: u8,
    applied_values: std.ArrayList(Value),
    prototype: *Prototype,
};

pub const String = struct {
    bytes: std.ArrayList(u8),
};

const std = @import("std");

test "simple values" {
    const testing = std.testing;

    const v14_: Value = Value.from_f64(14.0);

    try testing.expectEqual(Value.TRUE.is_int(), false);
    try testing.expectEqual(v14_.is_int(), false);
    try testing.expectEqual(Value.INT_ONE.get_int(), 1);
    try testing.expect(Value.new_int(42).is_int());
    try testing.expectEqual(Value.new_int(42).get_int(), 42);
    try testing.expect(v14_.is_number());
    try testing.expectEqual(v14_.get_f64(), 14.0);
}

test "heap closure value" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const closure: *Closure = try allocator.create(Closure);

    defer allocator.destroy(closure);

    const closure_value: Value = Value.new_closure(closure);

    try testing.expectEqual(closure_value.is_int(), false);
    try testing.expect(closure_value.is_ptr());
    try testing.expect(closure_value.is_closure());

    try testing.expectEqual(closure_value.get_closure(), closure);
}
