const std = @import("std");
const value = @import("value.zig");
const bytecode = @import("bytecode.zig");

const VmError = enum(u8) {
    ArityError,
    TypeError,
    StackUnderflow,
    InvalidInstruction,
};

const Continuation = enum(u8) {
    Continue,
    Halt,
    Error,
};

const TaggedContinuation = union(Continuation) {
    Continue,
    Halt,
    Error: VmError,
};

const FrameInfo = struct {
    stack_base: usize,
    local_base: usize,
};

const ptr = struct {
    pub fn replace(comptime T: type, dest: *T, src: T) T {
        const result = dest.*;
        dest.* = src;
        return result;
    }
};

const VmStack = struct {
    stack_base: usize,
    local_base: usize,
    stack: std.ArrayList(value.Value),

    pub fn init(allocator: std.mem.Allocator, locals: usize) VmStack {
        var stack = std.ArrayList(value.Value).init(allocator);
        stack.appendNTimes(value.Value.INT_ZERO, locals) catch @panic("Out of memory");
        return VmStack{
            .stack_base = locals,
            .local_base = 0,
            .stack = stack,
        };
    }

    pub fn deinit(self: *VmStack) void {
        self.stack.deinit();
    }

    pub fn push_frame(self: *VmStack, locals_len: usize) !FrameInfo {
        const new_local_base = self.stack.items.len;
        const new_stack_base = new_local_base + locals_len;

        try self.stack.ensureTotalCapacity(new_stack_base);
        self.stack.appendNTimesAssumeCapacity(value.Value.INT_ZERO, locals_len);

        return FrameInfo{
            .local_base = ptr.replace(usize, &self.local_base, new_local_base),
            .stack_base = ptr.replace(usize, &self.stack_base, new_stack_base),
        };
    }

    pub fn pop_frame(self: *VmStack, frame_info: FrameInfo) !void {
        try self.stack.replaceRange(self.local_base, self.stack_base - self.local_base, &.{});
        self.stack_base = frame_info.stack_base;
        self.local_base = frame_info.local_base;
    }

    pub fn load(self: *VmStack, index: usize) value.Value {
        return self.stack.items[self.local_base + index];
    }

    pub fn store(self: *VmStack, index: usize, v: value.Value) void {
        self.stack.items[self.local_base + index] = v;
    }

    pub fn push(self: *VmStack, v: value.Value) !void {
        try self.stack.append(v);
    }

    pub fn pop(self: *VmStack) value.Value {
        std.debug.assert(self.check_underflow(1) == false);
        return self.stack.pop().?;
    }

    pub fn pop_many(self: *VmStack, count: usize, allocator: std.mem.Allocator) ![]value.Value {
        std.debug.assert(self.check_underflow(count) == false);
        const start = self.stack.items.len - count;
        const popped = try allocator.alloc(value.Value, count);
        @memcpy(popped, self.stack.items[start..]);

        self.stack.shrinkRetainingCapacity(start);

        return popped;
    }

    pub fn check_underflow(self: *VmStack, count: usize) bool {
        std.debug.print("stack_base = {}, len = {}\n", .{ self.stack_base, self.stack.items.len });
        return self.stack.items.len -% count < self.stack_base;
    }
};

const Frame = struct {
    ip: usize,
    frame_info: FrameInfo,
    prototype: *value.Prototype,
};

const Cmp = enum(u8) { LT, EQ, GT };

fn compare(comptime T: type, a: T, b: T) Cmp {
    if (a > b) {
        return Cmp.GT;
    } else if (a < b) {
        return Cmp.LT;
    } else {
        return Cmp.EQ;
    }
}

pub const Machine = struct {
    ip: usize,
    prototype: *value.Prototype,
    frames: std.ArrayList(Frame),
    allocator: std.heap.ArenaAllocator,

    pub fn boot(allocator: std.mem.Allocator, prototype: *value.Prototype) !*Machine {
        const vm: *Machine = try allocator.create(Machine);
        vm.* = Machine{
            .ip = 0,
            .prototype = prototype,
            .frames = std.ArrayList(Frame).init(allocator),
            .allocator = std.heap.ArenaAllocator.init(allocator),
        };
        return vm;
    }

    pub fn deinit(self: *Machine, allocator: std.mem.Allocator) void {
        self.allocator.deinit();
        self.frames.deinit();
        allocator.destroy(self);
    }

    fn fetch(self: *Machine) u8 {
        const instruction = self.prototype.chunk.items[self.ip];
        self.ip += 1;
        return instruction;
    }

    fn read_u16(self: *Machine) u16 {
        const b0: u16 = @as(u16, self.prototype.chunk.items[self.ip]);
        const b1: u16 = @as(u16, self.prototype.chunk.items[self.ip + 1]);
        self.ip += 2;
        return b0 << 8 | b1;
    }

    pub fn run(self: *Machine, stack: *VmStack) !TaggedContinuation {
        var cont = try self.step(stack);
        loop: {
            while (cont == Continuation.Continue) : (cont = try self.step(stack)) {}
            break :loop;
        }

        return cont;
    }

    fn step(self: *Machine, stack: *VmStack) !TaggedContinuation {
        const ins = self.fetch();
        std.debug.print("ins = {s}\n", .{bytecode.TO_STRING[ins]});
        switch (ins) {
            bytecode.RETURN => {
                if (self.frames.items.len == 0) {
                    return Continuation.Halt;
                }

                const last_frame = self.frames.pop().?;
                try stack.pop_frame(last_frame.frame_info);
                self.ip = last_frame.ip;
                self.prototype = last_frame.prototype;
                return Continuation.Continue;
            },
            bytecode.ICONST_0 => {
                try stack.push(value.Value.INT_ZERO);
                return Continuation.Continue;
            },
            bytecode.ICONST_1 => {
                try stack.push(value.Value.INT_ONE);
                return Continuation.Continue;
            },
            bytecode.ADD => {
                const rhs = stack.pop();
                const lhs = stack.pop();

                if (lhs.is_int() and rhs.is_int()) {
                    const x = lhs.get_int();
                    const y = rhs.get_int();
                    try stack.push(value.Value.new_int(x + y));
                    std.debug.print("push = {}\n", .{stack.stack});
                    return Continuation.Continue;
                } else if (lhs.is_number() and rhs.is_number()) {
                    const x = lhs.get_f64();
                    const y = rhs.get_f64();
                    try stack.push(value.Value.from_f64(x + y));
                    std.debug.print("push = {}\n", .{stack.stack});
                    return Continuation.Continue;
                } else {
                    return TaggedContinuation{ .Error = .TypeError };
                }

                return Continuation.Continue;
            },
            bytecode.SUB => {
                const rhs = stack.pop();
                const lhs = stack.pop();

                if (lhs.is_int() and rhs.is_int()) {
                    const x = lhs.get_int();
                    const y = rhs.get_int();
                    try stack.push(value.Value.new_int(x - y));
                    std.debug.print("push = {}\n", .{stack.stack});
                    return Continuation.Continue;
                } else if (lhs.is_number() and rhs.is_number()) {
                    const x = lhs.get_f64();
                    const y = rhs.get_f64();
                    try stack.push(value.Value.from_f64(x - y));
                    std.debug.print("push = {}\n", .{stack.stack});
                    return Continuation.Continue;
                } else {
                    return TaggedContinuation{ .Error = .TypeError };
                }
            },
            bytecode.CLOSURE => {
                const proto: *value.Prototype = self.prototype.prototypes.items[self.read_u16()];
                const closure: *value.Closure = try self.allocator.allocator().create(value.Closure);
                closure.* = value.Closure{ .prototype = proto };
                const closure_value = value.Value.new_closure(closure);
                try stack.push(closure_value);
                return Continuation.Continue;
            },
            bytecode.CALL => {
                const argc = self.fetch();
                const callee = stack.pop();
                const arguments = try stack.pop_many(argc, self.allocator.allocator());

                if (callee.is_closure()) {
                    const closure = callee.get_closure();
                    const arity = closure.*.prototype.arity;
                    const locals = closure.*.prototype.locals;
                    switch (compare(u8, argc, arity)) {
                        .EQ => {
                            const frame_info = try stack.push_frame(locals);

                            @memcpy(stack.stack.items[stack.local_base..], arguments);
                            // for (0..arity) |index| {
                            //     stack.store(index, arguments[index]);
                            // }

                            try self.frames.append(Frame{
                                .ip = ptr.replace(usize, &self.ip, 0),
                                .prototype = ptr.replace(*value.Prototype, &self.prototype, closure.prototype),
                                .frame_info = frame_info,
                            });

                            return Continuation.Continue;
                        },
                        .LT => {
                            std.debug.print("here closure LT\n", .{});
                            const allocator = self.allocator.allocator();
                            const partial = try allocator.create(value.Partial);
                            partial.* = value.Partial{
                                .arity = arity,
                                .applied = argc,
                                .prototype = closure.prototype,
                                .applied_values = std.ArrayList(value.Value).init(allocator),
                            };

                            // try partial.applied_values.ensureTotalCapacity(arguments.len);
                            try partial.applied_values.appendSlice(arguments);
                            // @memcpy(partial.applied_values.items[0..argc], arguments);

                            const v = value.Value.new_partial(partial);
                            try stack.push(v);

                            return Continuation.Continue;
                        },
                        .GT => {
                            return TaggedContinuation{ .Error = .ArityError };
                        },
                    }
                } else if (callee.is_partial()) {
                    const partial = callee.get_partial();
                    const arity = partial.arity;
                    const applied = partial.applied;
                    const new_applied = applied + argc;

                    switch (compare(u8, new_applied, arity)) {
                        .GT => return TaggedContinuation{ .Error = .ArityError },
                        .EQ => {
                            std.debug.print("here partial EQ", .{});
                            var applied_values = try partial.applied_values.clone();
                            try applied_values.appendSlice(arguments);

                            const frame_info = try stack.push_frame(partial.prototype.locals);
                            @memcpy(stack.stack.items[stack.local_base..], applied_values.items);

                            try self.frames.append(Frame{
                                .ip = ptr.replace(usize, &self.ip, 0),
                                .frame_info = frame_info,
                                .prototype = ptr.replace(*value.Prototype, &self.prototype, partial.prototype),
                            });

                            return Continuation.Continue;
                        },
                        .LT => {
                            var applied_values = try partial.applied_values.clone();
                            try applied_values.appendSlice(arguments);
                            const allocator = self.allocator.allocator();

                            const new_partial = try allocator.create(value.Partial);
                            new_partial.* = value.Partial{
                                .arity = arity,
                                .applied = new_applied,
                                .prototype = partial.prototype,
                                .applied_values = applied_values,
                            };
                            const partial_value = value.Value.new_partial(new_partial);
                            try stack.push(partial_value);

                            return Continuation.Continue;
                        },
                    }
                } else {
                    return TaggedContinuation{ .Error = .TypeError };
                }
            },
            bytecode.LOAD_0 => {
                try stack.push(stack.load(0));
                return Continuation.Continue;
            },
            bytecode.LOAD_1 => {
                try stack.push(stack.load(1));
                return Continuation.Continue;
            },
            bytecode.LOAD_2 => {
                try stack.push(stack.load(2));
                return Continuation.Continue;
            },
            bytecode.LOAD_3 => {
                try stack.push(stack.load(3));
                return Continuation.Continue;
            },
            bytecode.LOAD_CONST => {
                const index = self.read_u16();
                const v = self.prototype.constants.items[index];
                switch (v) {
                    .Number => {
                        try stack.push(value.Value.from_f64(v.Number));
                    },
                }
                return Continuation.Continue;
            },
            bytecode.STORE_0 => {
                stack.store(0, stack.pop());
                return Continuation.Continue;
            },
            bytecode.STORE_1 => {
                stack.store(1, stack.pop());
                return Continuation.Continue;
            },
            bytecode.STORE_2 => {
                stack.store(2, stack.pop());
                return Continuation.Continue;
            },
            bytecode.STORE_3 => {
                stack.store(3, stack.pop());
                return Continuation.Continue;
            },
            bytecode.LOAD_N => {
                std.debug.print("todo", .{});
                return TaggedContinuation{ .Error = .InvalidInstruction };
            },
            bytecode.STORE_N => {
                std.debug.print("todo", .{});
                return TaggedContinuation{ .Error = .InvalidInstruction };
            },
            else => {
                std.debug.assert(false);
                return TaggedContinuation{ .Error = .InvalidInstruction };
            },
        }
    }
};

test "aaaa" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const prototype = value.Prototype.init(allocator);
    defer prototype.deinit(allocator);
    prototype.*.arity = 0;
    prototype.*.locals = 1;
    try prototype.*.constants.append(.{ .Number = 42 });
    try prototype.*.constants.append(.{ .Number = 40 });
    try prototype.*.chunk.append(bytecode.LOAD_CONST);
    try prototype.*.chunk.append(0x0);
    try prototype.*.chunk.append(0x0);
    try prototype.*.chunk.append(bytecode.CLOSURE);
    try prototype.*.chunk.append(0x0);
    try prototype.*.chunk.append(0x0);
    try prototype.*.chunk.append(bytecode.CALL);
    try prototype.*.chunk.append(0x1);
    try prototype.*.chunk.append(bytecode.STORE_0);
    try prototype.*.chunk.append(bytecode.LOAD_CONST);
    try prototype.*.chunk.append(0x0);
    try prototype.*.chunk.append(0x1);
    try prototype.*.chunk.append(bytecode.LOAD_0);
    try prototype.*.chunk.append(bytecode.CALL);
    try prototype.*.chunk.append(0x1);
    try prototype.*.chunk.append(bytecode.RETURN);

    const proto_add = value.Prototype.init(allocator);
    proto_add.*.arity = 2;
    proto_add.*.locals = 2;
    try prototype.*.prototypes.append(proto_add);
    try proto_add.*.chunk.append(bytecode.LOAD_0);
    try proto_add.*.chunk.append(bytecode.LOAD_1);
    try proto_add.*.chunk.append(bytecode.SUB);
    try proto_add.*.chunk.append(bytecode.RETURN);

    const vm = try Machine.boot(allocator, prototype);
    defer vm.deinit(allocator);

    var stack = VmStack.init(allocator, @as(usize, prototype.*.locals));
    defer stack.deinit();

    const continuation = try vm.run(&stack);
    const last = stack.pop();
    std.debug.print("{} with last = {}\n", .{ continuation, last.get_f64() });
}
