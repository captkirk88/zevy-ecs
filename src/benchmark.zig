const std = @import("std");

// Simple counting allocator for tracking allocations
const CountingAllocator = struct {
    /// Returns a duplicate of this allocator, preserving the underlying allocator but resetting stats
    pub fn duplicate(self: *const CountingAllocator) CountingAllocator {
        return create(self.allocator);
    }
    allocator: std.mem.Allocator,
    bytes_allocated: usize,
    allocs_count: usize,

    fn create(allocator: std.mem.Allocator) CountingAllocator {
        return CountingAllocator{
            .allocator = allocator,
            .bytes_allocated = 0,
            .allocs_count = 0,
        };
    }

    pub fn init(allocator: std.mem.Allocator) CountingAllocator {
        return create(allocator);
    }

    pub fn reset(self: *CountingAllocator) void {
        self.bytes_allocated = 0;
        self.allocs_count = 0;
    }

    pub fn alloc(self: *CountingAllocator, len: usize, ptr_align: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const result = self.allocator.rawAlloc(len, ptr_align, ret_addr);
        if (result) |_| {
            self.bytes_allocated += len;
            self.allocs_count += 1;
        }
        return result;
    }

    pub fn resize(self: *CountingAllocator, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const old_len = buf.len;
        const ok = self.allocator.rawResize(buf, buf_align, new_len, ret_addr);
        if (ok and new_len > old_len) {
            self.bytes_allocated += (new_len - old_len);
            self.allocs_count += 1;
        }
        return ok;
    }

    pub fn free(self: *CountingAllocator, buf: []u8, buf_align: std.mem.Alignment, ret_addr: usize) void {
        // Note: We don't subtract from bytes_allocated on free, as we want total allocations
        self.allocator.rawFree(buf, buf_align, ret_addr);
    }
};

const counting_vtable = std.mem.Allocator.VTable{
    .alloc = alloc,
    .resize = resize,
    .free = free,
    .remap = remap,
};

fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
    const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
    return self.alloc(len, alignment, ret_addr);
}

fn resize(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
    const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
    return self.resize(buf, buf_align, new_len, ret_addr);
}

fn free(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, ret_addr: usize) void {
    const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
    self.free(buf, buf_align, ret_addr);
}

fn remap(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
    const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
    // For simplicity, just resize and return the same pointer if possible
    if (self.resize(memory, alignment, new_len, ret_addr)) {
        return @as(?[*]u8, @ptrCast(memory.ptr));
    }
    return null;
}

/// Output format for benchmark results
pub const OutputFormat = enum {
    plain,
    markdown,
    html,
};

/// Simple benchmark utility for timing code execution and tracking memory usage
pub const Benchmark = struct {
    const Self = @This();
    allocator: std.mem.Allocator,
    counting_allocator: CountingAllocator,
    results: std.ArrayList(BenchmarkResult),

    pub const BenchmarkResult = struct {
        name: []const u8,
        duration_ns: u64,
        iterations: usize,
        avg_ns: u64,
        ops_per_iter: usize,
        total_bytes: usize,
        avg_bytes: usize,
        bytes_per_op: usize,
        allocs_per_op: usize,
    };

    /// Returns a std.mem.Allocator struct mapped to this benchmark's counting allocator methods
    ///
    /// Use this where any allocator is need to track allocations during benchmarking
    pub fn getCountingAllocator(self: *Self) std.mem.Allocator {
        return std.mem.Allocator{
            .ptr = &self.counting_allocator,
            .vtable = &counting_vtable,
        };
    }

    /// Initialize a Benchmark instance with the given allocator
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .counting_allocator = CountingAllocator.init(allocator),
            .results = std.ArrayList(BenchmarkResult).initCapacity(allocator, 0) catch @panic("Failed to init benchmark"),
        };
    }

    pub fn deinit(self: *Self) void {
        // Free each name string before deiniting the array
        for (self.results.items) |result| {
            self.allocator.free(result.name);
        }
        self.results.deinit(self.allocator);
        self.counting_allocator.reset();
    }

    /// Run a benchmark function multiple times and record the results
    pub fn run(self: *Self, name: []const u8, ops: usize, comptime func: anytype, args: anytype) !BenchmarkResult {
        const name_copy = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(name_copy);

        self.counting_allocator.reset();
        const start = std.time.nanoTimestamp();
        var i: usize = 0;
        while (i < ops) : (i += 1) {
            const return_type = @typeInfo(@TypeOf(func)).@"fn".return_type;
            if (return_type) |rt| {
                const return_type_info = @typeInfo(rt);
                if (return_type_info == .error_union) {
                    try @call(.auto, func, args);
                } else {
                    _ = @call(.auto, func, args);
                }
            } else {
                _ = @call(.auto, func, args);
            }
        }
        const end = std.time.nanoTimestamp();
        const total_duration = @as(u64, @intCast(end - start));
        const total_bytes = self.counting_allocator.bytes_allocated;
        const per_op_ns = if (ops > 0) total_duration / ops else 0;
        const per_op_bytes = if (ops > 0) total_bytes / ops else 0;

        const result = BenchmarkResult{
            .name = name_copy,
            .duration_ns = total_duration,
            .iterations = 1,
            .avg_ns = per_op_ns,
            .ops_per_iter = ops,
            .total_bytes = total_bytes,
            .avg_bytes = per_op_bytes,
            .bytes_per_op = per_op_bytes,
            .allocs_per_op = if (ops > 0) self.counting_allocator.allocs_count / ops else 0,
        };
        try self.results.append(self.allocator, result);
        return result;
    }

    pub fn getResults(self: *Self) []const BenchmarkResult {
        return self.results.items;
    }

    /// Format time value with appropriate unit
    fn formatTime(time_ns: u64) struct { value: f64, unit: []const u8 } {
        var time_val: f64 = @as(f64, @floatFromInt(time_ns));
        var unit: []const u8 = "ns";

        if (time_val >= 1_000_000_000.0) {
            unit = "s";
            time_val = time_val / 1_000_000_000.0;
        } else if (time_val >= 1_000_000.0) {
            unit = "ms";
            time_val = time_val / 1_000_000.0;
        } else if (time_val >= 1_000.0) {
            unit = "us";
            time_val = time_val / 1_000.0;
        }

        return .{ .value = time_val, .unit = unit };
    }

    /// Format memory value with appropriate unit
    fn formatMemory(bytes: usize) struct { value: f64, unit: []const u8 } {
        var mem_val: f64 = @floatFromInt(bytes);
        var unit: []const u8 = "B";

        if (mem_val >= 1024.0 * 1024.0) {
            unit = "MB";
            mem_val /= 1024.0 * 1024.0;
        } else if (mem_val >= 1024.0) {
            unit = "KB";
            mem_val /= 1024.0;
        }

        return .{ .value = mem_val, .unit = unit };
    }

    fn printResultPlain(result: BenchmarkResult) void {
        const time = formatTime(result.avg_ns);
        const mem = formatMemory(result.avg_bytes);

        std.debug.print("{s}\n", .{result.name});
        std.debug.print("ops: {d:>8} {d:>9.3} {s}/op {d:>9.3} {s}/op {d}/op\n", .{
            result.ops_per_iter,
            time.value,
            time.unit,
            mem.value,
            mem.unit,
            result.allocs_per_op,
        });
    }

    /// Print Markdown table header
    pub fn printMarkdownHeader() void {
        std.debug.print("| Benchmark | Operations | Time/op | Memory/op | Allocs/op\n", .{});
        std.debug.print("|-----------|------------|---------|----------|----------|\n", .{});
    }

    fn printResultMarkdown(result: BenchmarkResult) void {
        const time = formatTime(result.avg_ns);
        const mem = formatMemory(result.avg_bytes);

        std.debug.print("| {s} | {d} | {d:.3} {s}/op | {d:.3} {s}/op | {d}/op |\n", .{
            result.name,
            result.ops_per_iter,
            time.value,
            time.unit,
            mem.value,
            mem.unit,
            result.allocs_per_op,
        });
    }

    /// Print HTML document header
    pub fn printHtmlHeader() void {
        std.debug.print("<!DOCTYPE html>\n", .{});
        std.debug.print("<html>\n", .{});
        std.debug.print("<head>\n", .{});
        std.debug.print("  <title>Benchmark Results</title>\n", .{});
        std.debug.print("  <style>\n", .{});
        std.debug.print("    table {{ border-collapse: collapse; width: 100%; }}\n", .{});
        std.debug.print("    th, td {{ border: 1px solid #ddd; padding: 8px; text-align: left; }}\n", .{});
        std.debug.print("    th {{ background-color: #4CAF50; color: white; }}\n", .{});
        std.debug.print("    tr:nth-child(even) {{ background-color: #f2f2f2; }}\n", .{});
        std.debug.print("  </style>\n", .{});
        std.debug.print("</head>\n", .{});
        std.debug.print("<body>\n", .{});
        std.debug.print("  <h1>Benchmark Results</h1>\n", .{});
        std.debug.print("  <table>\n", .{});
        std.debug.print("    <tr>\n", .{});
        std.debug.print("      <th>Benchmark</th>\n", .{});
        std.debug.print("      <th>Operations</th>\n", .{});
        std.debug.print("      <th>Time/op</th>\n", .{});
        std.debug.print("      <th>Memory/op</th>\n", .{});
        std.debug.print("      <th>Allocs/op</th>\n", .{});
        std.debug.print("    </tr>\n", .{});
    }

    /// Print HTML document footer
    pub fn printHtmlFooter() void {
        std.debug.print("  </table>\n", .{});
        std.debug.print("</body>\n", .{});
        std.debug.print("</html>\n", .{});
    }

    fn printResultHtml(result: BenchmarkResult) void {
        const time = formatTime(result.avg_ns);
        const mem = formatMemory(result.avg_bytes);

        std.debug.print("  <tr>\n", .{});
        std.debug.print("    <td>{s}</td>\n", .{result.name});
        std.debug.print("    <td>{d}</td>\n", .{result.ops_per_iter});
        std.debug.print("    <td>{d:.3} {s}/op</td>\n", .{ time.value, time.unit });
        std.debug.print("    <td>{d:.3} {s}/op</td>\n", .{ mem.value, mem.unit });
        std.debug.print("    <td>{d}/op</td>\n", .{result.allocs_per_op});
        std.debug.print("  </tr>\n", .{});
    }

    /// Print a single benchmark result (legacy, defaults to plain text)
    pub fn printResult(result: BenchmarkResult) void {
        printResultPlain(result);
    }

    pub fn printResultFormatted(result: BenchmarkResult, format: OutputFormat) void {
        switch (format) {
            .plain => printResultPlain(result),
            .markdown => printResultMarkdown(result),
            .html => printResultHtml(result),
        }
    }

    /// Print benchmark results with specified format
    pub fn printResultsFormatted(self: *Self, format: OutputFormat) void {
        switch (format) {
            .plain => {
                std.debug.print("Benchmark Results:\n", .{});
                for (self.results.items) |result| {
                    printResultPlain(result);
                }
            },
            .markdown => {
                std.debug.print("# Benchmark Results\n\n", .{});
                printMarkdownHeader();
                for (self.results.items) |result| {
                    printResultMarkdown(result);
                }
                std.debug.print("\n", .{});
            },
            .html => {
                printHtmlHeader();
                for (self.results.items) |result| {
                    printResultHtml(result);
                }
                printHtmlFooter();
            },
        }
    }

    /// Print benchmark results (legacy, defaults to plain text)
    pub fn printResults(self: *Self) void {
        self.printResultsFormatted(.plain);
    }
};
