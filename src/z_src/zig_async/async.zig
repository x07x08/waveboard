const std = @import("std");

fn spawn_call(fun: anytype, args: anytype) void {
    _ = @call(.auto, fun, args);
}

/// Async task without return
pub fn Spawn(fun: anytype, args: anytype) !void {
    var thread = try std.Thread.spawn(.{}, spawn_call, .{ fun, args });

    thread.detach();
}

fn task_call(fun: anytype, args: anytype, then_fun: anytype, then_args: anytype) void {
    const ret = @call(.auto, fun, args);

    _ = @call(.auto, then_fun, .{ret} ++ then_args);
}

/// Async task with callback (`fn (ret: <fun return type>, then_args...) void`)
pub fn Task(fun: anytype, args: anytype, then_fun: anytype, then_args: anytype) !void {
    var thread = try std.Thread.spawn(.{}, task_call, .{ fun, args, then_fun, then_args });

    thread.detach();
}

fn waitFunc(db: *DebounceData, fun: anytype) void {
    while (true) {
        db.wait.timedWait(db.timeNs) catch {
            break;
        };

        db.wait.reset();
    }

    _ = @call(.auto, fun, .{});

    db.spawned = false;
}

const DebounceData = struct {
    timeNs: u64,
    spawned: bool = false,
    wait: std.Thread.ResetEvent = .{},
};

pub fn Debouncer(timeNs: u64, td: *const fn () void) type {
    return struct {
        data: DebounceData = .{ .timeNs = timeNs },
        fun: @TypeOf(td) = td,

        const Self = @This();

        pub fn call(self: *Self) void {
            if (!self.data.spawned) {
                self.data.spawned = true;

                Spawn(waitFunc, .{ &self.data, self.fun }) catch unreachable;
            } else {
                self.data.wait.set();
            }
        }
    };
}

fn tickFunc(td: *TickData, fun: anytype) void {
    while (true) {
        if (((td.terminate != null) and
            (td.terminate.?.* == true)) or
            (td.forceTerminate == true))
        {
            td.forceTerminate = false;

            break;
        }

        td.wait.timedWait(td.timeNs) catch {};

        _ = @call(.auto, fun, .{});
    }
}

const TickData = struct {
    timeNs: u64,
    forceTerminate: bool = false,
    wait: std.Thread.ResetEvent = .{},
    terminate: ?*bool = null,
};

pub fn Ticker(timeNs: u64, td: *const fn () void) type {
    return struct {
        data: TickData = .{ .timeNs = timeNs },
        fun: @TypeOf(td) = td,

        const Self = @This();

        pub fn call(self: *Self) void {
            Spawn(tickFunc, .{ &self.data, self.fun }) catch unreachable;
        }
    };
}
