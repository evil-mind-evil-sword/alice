const std = @import("std");
const tissue = @import("tissue");
const idle = @import("idle");
const extractJsonString = idle.event_parser.extractString;
const jwz = idle.jwz_utils;

/// SubagentStop hook - handles alice subagent completion
/// When alice finishes reviewing, posts status to jwz.
/// For non-alice subagents, allows exit without review.
pub fn run(allocator: std.mem.Allocator) !u8 {
    // Read hook input from stdin
    const stdin = std.fs.File.stdin();
    var buf: [65536]u8 = undefined;
    const n = try stdin.readAll(&buf);
    const input_json = buf[0..n];

    // Extract cwd and change to project directory
    const cwd = extractJsonString(input_json, "\"cwd\"") orelse ".";
    std.posix.chdir(cwd) catch {};

    // Extract session_id and subagent info
    const session_id = extractJsonString(input_json, "\"session_id\"") orelse "unknown";
    const subagent_type = extractJsonString(input_json, "\"subagent_type\"");
    const prompt = extractJsonString(input_json, "\"prompt\"");

    // Check if this is alice
    if (isAliceSubagent(subagent_type, prompt)) {
        // Alice just finished reviewing - post status based on issues created
        const open_issues = countOpenAliceReviewIssues(allocator);
        if (open_issues > 0) {
            jwz.postAliceStatus(allocator, session_id, "issues");
        } else {
            jwz.postAliceStatus(allocator, session_id, "complete");
        }
        // Always allow alice to exit (no recursive review)
        return 0;
    }

    // Non-alice subagent - allow exit without review
    // Main agent's stop hook will handle alice invocation
    return 0;
}

/// Check if this subagent is alice
fn isAliceSubagent(subagent_type: ?[]const u8, prompt: ?[]const u8) bool {
    // Check subagent_type first (most reliable)
    if (subagent_type) |st| {
        if (std.mem.indexOf(u8, st, "alice") != null) return true;
        if (std.mem.eql(u8, st, "idle:alice")) return true;
    }

    // Fall back to prompt content check
    if (prompt) |p| {
        // Check for alice markers in prompt
        if (std.mem.indexOf(u8, p, "You are alice") != null) return true;
        if (std.mem.indexOf(u8, p, "alice, an adversarial reviewer") != null) return true;
    }

    return false;
}

fn countOpenAliceReviewIssues(allocator: std.mem.Allocator) u32 {
    const store_dir = tissue.store.discoverStoreDir(allocator) catch return 0;
    defer allocator.free(store_dir);

    var store = tissue.store.Store.open(allocator, store_dir) catch return 0;
    defer store.deinit();

    return store.countOpenIssuesByTag("alice-review") catch 0;
}
