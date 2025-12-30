const std = @import("std");
const zawinski = @import("zawinski");
const tissue = @import("tissue");

/// Result of auto-land attempt
pub const AutoLandResult = enum {
    success,
    no_worktree,
    dirty_worktree,
    branch_not_found,
    ff_failed,
    push_failed,
    update_ref_failed,
};

/// Auto-land a completed issue: merge branch to base, push, cleanup
pub fn autoLand(
    allocator: std.mem.Allocator,
    issue_id: []const u8,
    worktree_path: []const u8,
    branch: []const u8,
    base_ref: []const u8,
) AutoLandResult {
    // Derive main repo root from worktree path
    // WORKTREE_PATH format: /path/to/repo/.worktrees/idle/<issue-id>
    const worktrees_suffix = "/.worktrees/idle/";
    const main_repo = blk: {
        if (std.mem.indexOf(u8, worktree_path, worktrees_suffix)) |idx| {
            break :blk worktree_path[0..idx];
        }
        return .no_worktree;
    };

    // Verify worktree is clean
    if (!isWorktreeClean(allocator, worktree_path)) {
        postMessage(allocator, issue_id, "[loop] AUTO_LAND_FAILED: Worktree has uncommitted changes");
        return .dirty_worktree;
    }

    // Fetch from origin
    _ = runGitCommand(allocator, main_repo, &.{ "fetch", "origin" });

    // Get branch tip
    const branch_tip = getRef(allocator, main_repo, branch) orelse {
        postMessage(allocator, issue_id, "[loop] AUTO_LAND_FAILED: Branch not found");
        return .branch_not_found;
    };
    defer allocator.free(branch_tip);

    // Get origin base ref
    var origin_base_ref_buf: [128]u8 = undefined;
    const origin_base_ref = std.fmt.bufPrint(&origin_base_ref_buf, "refs/remotes/origin/{s}", .{base_ref}) catch return .ff_failed;
    const origin_base = getRef(allocator, main_repo, origin_base_ref);
    defer if (origin_base) |b| allocator.free(b);

    // Check if branch is fast-forwardable from origin base
    if (origin_base) |ob| {
        if (!isFastForward(allocator, main_repo, ob, branch_tip)) {
            postMessage(allocator, issue_id, "[loop] AUTO_LAND_FAILED: Cannot fast-forward. Rebase needed.");
            return .ff_failed;
        }
    }

    // Update local base_ref to origin if behind
    if (origin_base) |ob| {
        var update_cmd_buf: [256]u8 = undefined;
        const local_ref = std.fmt.bufPrint(&update_cmd_buf, "refs/heads/{s}", .{base_ref}) catch return .update_ref_failed;
        _ = runGitCommand(allocator, main_repo, &.{ "update-ref", local_ref, ob });
    }

    // Fast-forward base_ref to branch tip
    var base_ref_buf: [128]u8 = undefined;
    const local_base_ref = std.fmt.bufPrint(&base_ref_buf, "refs/heads/{s}", .{base_ref}) catch return .update_ref_failed;

    if (runGitCommand(allocator, main_repo, &.{ "update-ref", local_base_ref, branch_tip }) != 0) {
        return .update_ref_failed;
    }

    // Push to remote
    if (runGitCommand(allocator, main_repo, &.{ "push", "origin", base_ref }) != 0) {
        postMessage(allocator, issue_id, "[loop] AUTO_LAND_FAILED: Push rejected");
        return .push_failed;
    }

    // Clean up worktree
    _ = runGitCommand(allocator, main_repo, &.{ "worktree", "remove", worktree_path });

    // Clean up branch
    _ = runGitCommand(allocator, main_repo, &.{ "branch", "-d", branch });

    // Update tissue status
    closeTissueIssue(allocator, issue_id);

    // Post success message
    var msg_buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrint(&msg_buf, "[loop] LANDED: Merged to {s}", .{base_ref}) catch "[loop] LANDED";
    postMessage(allocator, issue_id, msg);

    return .success;
}

fn isWorktreeClean(allocator: std.mem.Allocator, path: []const u8) bool {
    // Check for unstaged changes
    const diff_result = runGitCommandInDir(allocator, path, &.{ "diff", "--quiet" });
    if (diff_result != 0) return false;

    // Check for staged changes
    const cached_result = runGitCommandInDir(allocator, path, &.{ "diff", "--cached", "--quiet" });
    return cached_result == 0;
}

fn getRef(allocator: std.mem.Allocator, repo: []const u8, ref: []const u8) ?[]u8 {
    var child = std.process.Child.init(
        &.{ "git", "-C", repo, "rev-parse", ref },
        allocator,
    );
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;

    child.spawn() catch return null;

    var buf: [64]u8 = undefined;
    const n = child.stdout.?.readAll(&buf) catch 0;
    _ = child.wait() catch return null;

    if (n == 0) return null;

    // Trim newline
    var end = n;
    while (end > 0 and (buf[end - 1] == '\n' or buf[end - 1] == '\r')) {
        end -= 1;
    }

    const result = allocator.dupe(u8, buf[0..end]) catch return null;
    return result;
}

fn isFastForward(allocator: std.mem.Allocator, repo: []const u8, base: []const u8, tip: []const u8) bool {
    var child = std.process.Child.init(
        &.{ "git", "-C", repo, "merge-base", "--is-ancestor", base, tip },
        allocator,
    );
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;

    child.spawn() catch return false;
    const term = child.wait() catch return false;
    return term.Exited == 0;
}

fn runGitCommand(allocator: std.mem.Allocator, repo: []const u8, args: []const []const u8) u8 {
    var full_args: [16][]const u8 = undefined;
    full_args[0] = "git";
    full_args[1] = "-C";
    full_args[2] = repo;
    for (args, 0..) |arg, i| {
        full_args[3 + i] = arg;
    }

    var child = std.process.Child.init(full_args[0 .. 3 + args.len], allocator);
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;

    child.spawn() catch return 1;
    const term = child.wait() catch return 1;
    return term.Exited;
}

fn runGitCommandInDir(allocator: std.mem.Allocator, dir: []const u8, args: []const []const u8) u8 {
    return runGitCommand(allocator, dir, args);
}

fn postMessage(allocator: std.mem.Allocator, issue_id: []const u8, message: []const u8) void {
    const store_dir = zawinski.store.discoverStoreDir(allocator) catch return;
    defer allocator.free(store_dir);

    var store = zawinski.store.Store.open(allocator, store_dir) catch return;
    defer store.deinit();

    var topic_buf: [128]u8 = undefined;
    const topic = std.fmt.bufPrint(&topic_buf, "issue:{s}", .{issue_id}) catch return;

    // Ensure topic exists
    _ = store.fetchTopic(topic) catch |err| {
        if (err == zawinski.store.StoreError.TopicNotFound) {
            const tid = store.createTopic(topic, "") catch return;
            allocator.free(tid);
        } else return;
    };

    const sender = zawinski.store.Sender{
        .id = "idle",
        .name = "idle",
        .model = null,
        .role = "loop",
    };

    const msg_id = store.createMessage(topic, null, message, .{ .sender = sender }) catch return;
    allocator.free(msg_id);
}

fn closeTissueIssue(allocator: std.mem.Allocator, issue_id: []const u8) void {
    const store_dir = tissue.store.discoverStoreDir(allocator) catch return;
    defer allocator.free(store_dir);

    var store = tissue.store.Store.open(allocator, store_dir) catch return;
    defer store.deinit();

    store.updateIssue(issue_id, null, null, "closed", null, &.{}, &.{}) catch {};
}
