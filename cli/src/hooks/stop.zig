const std = @import("std");
const tissue = @import("tissue");
const idle = @import("idle");
const extractJsonString = idle.event_parser.extractString;
const jwz = idle.jwz_utils;

/// Stop hook - quality gate via alice review
/// Directs agent to invoke alice, allows only when no issues remain after review.
pub fn run(allocator: std.mem.Allocator) !u8 {
    // Read hook input from stdin
    const stdin = std.fs.File.stdin();
    var buf: [65536]u8 = undefined;
    const n = try stdin.readAll(&buf);
    const input_json = buf[0..n];

    // Extract cwd and change to project directory
    const cwd = extractJsonString(input_json, "\"cwd\"") orelse ".";
    std.posix.chdir(cwd) catch {};

    // Extract session_id for alice status tracking
    const session_id = extractJsonString(input_json, "\"session_id\"") orelse "unknown";

    // Check for open alice-review issues
    const open_issues = countOpenAliceReviewIssues(allocator);

    // If issues exist, block and tell agent to fix them
    if (open_issues > 0) {
        // Clear alice status so next review is fresh
        jwz.clearAliceStatus(allocator, session_id);
        return blockWithReason(
            \\[ISSUES REMAIN] {} open alice-review issue(s) exist.
            \\
            \\Fix all issues, then exit will be allowed.
            \\Run `tissue list -t alice-review` to see them.
        , .{open_issues});
    }

    // Check alice review status
    const alice_status = jwz.readAliceStatus(allocator, session_id);

    if (alice_status) |status| {
        if (std.mem.eql(u8, status, "complete")) {
            // Alice reviewed and found no issues - allow exit
            jwz.clearAliceStatus(allocator, session_id);
            return 0;
        }
    }

    // No alice review yet, or previous review found issues that are now fixed
    // Direct agent to invoke alice for review
    return blockWithReason(
        \\[REVIEW REQUIRED] Invoke alice for review before exit.
        \\
        \\Use the Task tool to spawn alice:
        \\  Task(subagent_type="idle:alice", prompt="Review the work done in this session")
        \\
        \\Alice will review and create issues if problems are found.
    , .{});
}

/// Block exit with a formatted reason
fn blockWithReason(comptime fmt: []const u8, args: anytype) u8 {
    var reason_buf: [4096]u8 = undefined;
    const reason = std.fmt.bufPrint(&reason_buf, fmt, args) catch return 2;

    var stdout_buf: [8192]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const stdout = &stdout_writer.interface;

    stdout.writeAll("{\"decision\":\"block\",\"reason\":\"") catch return 2;
    escapeJsonTo(stdout, reason) catch return 2;
    stdout.writeAll("\"}\n") catch return 2;
    stdout.flush() catch return 2;

    return 2;
}

/// Escape string for JSON output
fn escapeJsonTo(writer: anytype, data: []const u8) !void {
    for (data) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => {
                if (c < 0x20) {
                    try writer.print("\\u{x:0>4}", .{c});
                } else {
                    try writer.writeByte(c);
                }
            },
        }
    }
}

/// Count open alice-review issues
fn countOpenAliceReviewIssues(allocator: std.mem.Allocator) u32 {
    const store_dir = tissue.store.discoverStoreDir(allocator) catch return 0;
    defer allocator.free(store_dir);

    var store = tissue.store.Store.open(allocator, store_dir) catch return 0;
    defer store.deinit();

    return store.countOpenIssuesByTag("alice-review") catch 0;
}
