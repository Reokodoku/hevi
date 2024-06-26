const std = @import("std");
const hevi = @import("hevi");
const argparse = @import("argparse.zig");
const options = @import("options.zig");

pub const std_options = std.Options{
    .logFn = logFn,
};

fn logFn(comptime message_level: std.log.Level, comptime scope: @Type(.EnumLiteral), comptime format: []const u8, args: anytype) void {
    const level_txt = comptime message_level.asText();
    const prefix2 = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
    const stderr = std.io.getStdErr();
    var bw = std.io.bufferedWriter(stderr.writer());
    const writer = bw.writer();

    std.debug.lockStdErr();
    defer std.debug.unlockStdErr();

    const log_color = stderr.supportsAnsiEscapeCodes();

    nosuspend {
        writer.print(
            "{s}" ++ level_txt ++ "{s}",
            if (log_color) .{ "\x1b[31m\x1b[1m", "\x1b[0m" } else .{ "", "" },
        ) catch return;
        writer.print(prefix2 ++ format ++ "\n", args) catch return;
        bw.flush() catch return;
    }
}

pub fn fail(comptime fmt: []const u8, args: anytype) noreturn {
    std.log.err(fmt, args);
    std.process.exit(1);
}

pub fn main() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() == .leak) fail("Memory leak detected", .{});

    const allocator = gpa.allocator();

    const args = std.process.argsAlloc(allocator) catch fail("Out of memory", .{});
    defer std.process.argsFree(allocator, args);

    const parsed_args = argparse.parse(args[1..]);

    const file = std.fs.cwd().openFile(parsed_args.filename, .{}) catch |err| switch (err) {
        error.FileNotFound => fail("{s} not found", .{parsed_args.filename}),
        error.IsDir => fail("{s} is a directory", .{parsed_args.filename}),
        else => fail("{s} could not be opened", .{parsed_args.filename}),
    };
    defer file.close();

    const data = file.readToEndAlloc(allocator, std.math.maxInt(usize)) catch fail("Out of memory", .{});
    defer allocator.free(data);

    const stdout = std.io.getStdOut();

    const opts = options.getOptions(allocator, parsed_args, stdout) catch |err| switch (err) {
        error.InvalidConfig => fail("Invalid config found", .{}),
        else => fail("Error getting options and config file", .{}),
    };

    hevi.dump(allocator, data, stdout.writer().any(), opts) catch |err| switch (err) {
        error.NonMatchingParser => fail("{s} does not match parser {s}", .{ parsed_args.filename, @tagName(opts.parser.?) }),
        else => fail("{s}", .{@errorName(err)}),
    };
}

test {
    _ = argparse;
    _ = options;
}
