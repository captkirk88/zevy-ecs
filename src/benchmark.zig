const std = @import("std");
const mem = @import("zevy_mem");

const CountingAllocator = mem.CountingAllocator;

/// Output format for benchmark results
pub const OutputFormat = enum {
    plain,
    markdown,
    html,
};

/// Simple benchmark utility for timing code execution and tracking memory usage
pub const Benchmark = struct {
    const Self = @This();
    base_allocator: std.mem.Allocator,
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

        pub fn format(self: *const BenchmarkResult, writer: *std.io.Writer) []const u8 {
            return writer.print(
                "{s}: {d} ns total, {d} ns/op, {f} total, {f}/op, {d} allocs/op",
                .{
                    self.name,
                    self.duration_ns,
                    self.avg_ns,
                    mem.byteSize(self.total_bytes),
                    mem.byteSize(self.avg_bytes),
                    self.allocs_per_op,
                },
            ) catch |err| {
                "Error formatting benchmark result: " ++ @errorName(err);
            };
        }
    };

    /// Get the counting allocator's interface used for benchmarking
    pub fn allocator(self: *Self) std.mem.Allocator {
        return self.counting_allocator.allocator();
    }

    /// Initialize a Benchmark instance with the given allocator
    pub fn init(base_allocator: std.mem.Allocator) Self {
        return Self{
            .base_allocator = base_allocator,
            .counting_allocator = CountingAllocator.init(base_allocator),
            .results = std.ArrayList(BenchmarkResult).initCapacity(base_allocator, 0) catch @panic("Failed to init benchmark"),
        };
    }

    pub fn deinit(self: *Self) void {
        // Free each name string before deiniting the array
        for (self.results.items) |result| {
            self.base_allocator.free(result.name);
        }
        self.results.deinit(self.base_allocator);
        self.counting_allocator.reset();
    }

    /// Run a benchmark function multiple times and record the results
    pub fn run(self: *Self, name: []const u8, ops: usize, comptime func: anytype, args: anytype) !BenchmarkResult {
        const name_copy = try self.base_allocator.dupe(u8, name);
        errdefer self.base_allocator.free(name_copy);

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
        try self.results.append(self.base_allocator, result);
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

    fn printResultPlain(result: BenchmarkResult) void {
        const time = formatTime(result.avg_ns);
        const mem_size = mem.byteSize(result.avg_bytes);

        std.debug.print("{s}\n", .{result.name});
        std.debug.print("ops: {d:>8} {d:>9.3} {s}/op {f}/op {d}/op\n", .{
            result.ops_per_iter,
            time.value,
            time.unit,
            mem_size,
            result.allocs_per_op,
        });
    }

    /// Print Markdown table header
    pub fn printMarkdownHeader() void {
        std.debug.print("| Benchmark | Operations | Time/op | Memory/op | Allocs/op\n", .{});
        std.debug.print("|-----------|------------|---------|----------|----------|\n", .{});
    }

    pub fn printMarkdownHeaderWithTitle(title: []const u8) void {
        std.debug.print("#### {s}\n\n", .{title});
        Self.printMarkdownHeader();
    }

    fn printResultMarkdown(result: BenchmarkResult) void {
        const time = formatTime(result.avg_ns);
        const mem_size = mem.byteSize(result.avg_bytes);

        std.debug.print("| {s} | {d} | {d:.3} {s}/op | {f}/op | {d}/op |\n", .{
            result.name,
            result.ops_per_iter,
            time.value,
            time.unit,
            mem_size,
            result.allocs_per_op,
        });
    }

    /// Print HTML document header
    pub fn printHtmlHeader() void {
        Self.printHtmlHeaderWithTitle("Benchmark Results");
    }

    pub fn printHtmlHeaderWithTitle(title: []const u8) void {
        std.debug.print("<!DOCTYPE html>\n", .{});
        std.debug.print("<html>\n", .{});
        std.debug.print("<head>\n", .{});
        std.debug.print("  <title>{s}</title>\n", .{title});
        std.debug.print("  <style>\n", .{});
        std.debug.print("    table {{ border-collapse: collapse; width: 100%; }}\n", .{});
        std.debug.print("    th, td {{ border: 1px solid #ddd; padding: 8px; text-align: left; }}\n", .{});
        std.debug.print("    th {{ background-color: #4CAF50; color: white; }}\n", .{});
        std.debug.print("    tr:nth-child(even) {{ background-color: #f2f2f2; }}\n", .{});
        std.debug.print("  </style>\n", .{});
        std.debug.print("</head>\n", .{});
        std.debug.print("<body>\n", .{});
        std.debug.print("  <h1>{s}</h1>\n", .{title});
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
        const mem_size = mem.byteSize(result.avg_bytes);

        std.debug.print("  <tr>\n", .{});
        std.debug.print("    <td>{s}</td>\n", .{result.name});
        std.debug.print("    <td>{d}</td>\n", .{result.ops_per_iter});
        std.debug.print("    <td>{d:.3} {s}/op</td>\n", .{ time.value, time.unit });
        std.debug.print("    <td>{f}/op</td>\n", .{mem_size});
        std.debug.print("    <td>{d}/op</td>\n", .{result.allocs_per_op});
        std.debug.print("  </tr>\n", .{});
    }

    pub fn printResult(result: BenchmarkResult, format: OutputFormat) void {
        switch (format) {
            .plain => printResultPlain(result),
            .markdown => printResultMarkdown(result),
            .html => printResultHtml(result),
        }
    }

    /// Print benchmark results with specified format
    pub fn printResults(self: *Self, format: OutputFormat) void {
        switch (format) {
            .plain => {
                for (self.results.items) |result| {
                    printResultPlain(result);
                }
            },
            .markdown => {
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
};
