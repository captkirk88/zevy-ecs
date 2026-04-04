const std = @import("std");
const mem = @import("zevy_mem");

const CountingAllocator = mem.allocators.CountingAllocator;
const Self = @This();

/// Output format for benchmark results
pub const OutputFormat = enum {
    plain,
    markdown,
    html,

    pub fn fileExtension(self: OutputFormat) []const u8 {
        return switch (self) {
            .plain => "txt",
            .markdown => "md",
            .html => "html",
        };
    }
};

pub const ReportOptions = struct {
    directory: []const u8 = "reports",
    basename: []const u8 = "benchmark_report",
    file_name: ?[]const u8 = null,
    title: []const u8 = "Benchmark Results",
};

base_allocator: std.mem.Allocator,
counting_allocator: CountingAllocator,
output_format: OutputFormat,
current_section: ?[]const u8,
results: std.ArrayList(BenchmarkResult),

pub const BenchmarkResult = struct {
    section: ?[]const u8,
    name: []const u8,
    duration_ns: u64,
    iterations: usize,
    avg_ns: u64,
    ops_per_iter: usize,
    total_bytes: usize,
    avg_bytes: usize,
    bytes_per_op: usize,
    allocs_per_op: usize,

    pub fn print(self: *const BenchmarkResult, writer: *std.Io.Writer, format: OutputFormat) !void {
        try writeResult(writer, self.*, format);
    }
};

/// Get the counting allocator's interface used for benchmarking
pub fn allocator(self: *Self) std.mem.Allocator {
    return self.counting_allocator.allocator();
}

/// Initialize a Benchmark instance with the given allocator and output format.
pub fn init(base_allocator: std.mem.Allocator, output_format: OutputFormat) Self {
    return Self{
        .base_allocator = base_allocator,
        .counting_allocator = CountingAllocator.init(base_allocator),
        .output_format = output_format,
        .current_section = null,
        .results = std.ArrayList(BenchmarkResult).initCapacity(base_allocator, 0) catch @panic("Failed to init benchmark"),
    };
}

pub fn initWithAllocator(base_allocator: std.mem.Allocator, counting_allocator: CountingAllocator, output_format: OutputFormat) Self {
    return Self{
        .base_allocator = base_allocator,
        .counting_allocator = counting_allocator,
        .output_format = output_format,
        .current_section = null,
        .results = std.ArrayList(BenchmarkResult).initCapacity(base_allocator, 0) catch @panic("Failed to init benchmark"),
    };
}

pub fn deinit(self: *Self) void {
    // Free each name string before deiniting the array
    for (self.results.items) |result| {
        if (result.section) |section| self.base_allocator.free(section);
        self.base_allocator.free(result.name);
    }
    if (self.current_section) |section| self.base_allocator.free(section);
    self.results.deinit(self.base_allocator);
    self.counting_allocator.reset();
}

pub fn beginSection(self: *Self, title: []const u8) !void {
    const title_copy = try self.base_allocator.dupe(u8, title);
    errdefer self.base_allocator.free(title_copy);

    if (self.current_section) |existing| {
        self.base_allocator.free(existing);
    }
    self.current_section = title_copy;
}

pub fn clearSection(self: *Self) void {
    if (self.current_section) |section| {
        self.base_allocator.free(section);
        self.current_section = null;
    }
}

fn measureNow() std.Io.Timestamp {
    var threaded: std.Io.Threaded = undefined;
    const io = threaded.io();
    return std.Io.Timestamp.now(io, std.Io.Clock.awake);
}

fn callBenchmark(comptime func: anytype, args: anytype) anyerror!void {
    const return_type = @typeInfo(@TypeOf(func)).@"fn".return_type;
    if (return_type) |rt| {
        if (@typeInfo(rt) == .error_union) {
            try @call(.auto, func, args);
        } else {
            _ = @call(.auto, func, args);
        }
    } else {
        _ = @call(.auto, func, args);
    }
}

fn sortU64(values: []u64) void {
    var i: usize = 1;
    while (i < values.len) : (i += 1) {
        const key = values[i];
        var j = i;
        while (j > 0 and values[j - 1] > key) : (j -= 1) {
            values[j] = values[j - 1];
        }
        values[j] = key;
    }
}

/// Run a benchmark function multiple times and record the results
pub fn run(self: *Self, name: []const u8, ops: usize, comptime func: anytype, args: anytype) !BenchmarkResult {
    const name_copy = try self.base_allocator.dupe(u8, name);
    errdefer self.base_allocator.free(name_copy);

    const section_copy = if (self.current_section) |section|
        try self.base_allocator.dupe(u8, section)
    else
        null;
    errdefer if (section_copy) |section| self.base_allocator.free(section);

    const timing_sample_count = if (ops == 0) @as(usize, 1) else @min(ops, 5);
    var sample_times = try self.base_allocator.alloc(u64, timing_sample_count);
    defer self.base_allocator.free(sample_times);

    self.counting_allocator.reset();
    var total_duration: u64 = 0;
    var completed_ops: usize = 0;
    var sample_index: usize = 0;
    while (sample_index < timing_sample_count) : (sample_index += 1) {
        const remaining_ops = ops - completed_ops;
        const remaining_samples = timing_sample_count - sample_index;
        const batch_ops = if (remaining_ops == 0) 0 else @max(remaining_ops / remaining_samples, 1);

        const start = measureNow();
        var batch_index: usize = 0;
        while (batch_index < batch_ops) : (batch_index += 1) {
            try callBenchmark(func, args);
        }

        const end = measureNow();
        const batch_duration = @as(u64, @intCast(start.durationTo(end).nanoseconds));
        total_duration += batch_duration;
        sample_times[sample_index] = if (batch_ops > 0) batch_duration / batch_ops else 0;
        completed_ops += batch_ops;
    }

    sortU64(sample_times);
    const median_index = sample_times.len / 2;
    const per_op_ns = if (sample_times.len == 0)
        0
    else if (sample_times.len % 2 == 1)
        sample_times[median_index]
    else
        @as(u64, @intCast((@as(u128, sample_times[median_index - 1]) + sample_times[median_index]) / 2));

    const total_bytes = self.counting_allocator.bytes_allocated;
    const per_op_bytes = if (ops > 0) total_bytes / ops else 0;

    const result = BenchmarkResult{
        .section = section_copy,
        .name = name_copy,
        .duration_ns = total_duration,
        .iterations = timing_sample_count,
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

pub fn print(self: *const Self, writer: *std.Io.Writer) !void {
    try self.printWithTitle(writer, "Benchmark Results");
}

pub fn printWithTitle(self: *const Self, writer: *std.Io.Writer, title: []const u8) !void {
    switch (self.output_format) {
        .html => try self.printHtml(writer, title),
        else => try self.printText(writer, title),
    }
}

pub fn writeReport(self: *const Self, io: std.Io) !void {
    try self.writeReportWithOptions(io, .{});
}

pub fn writeReportWithOptions(self: *const Self, io: std.Io, options: ReportOptions) !void {
    try std.Io.Dir.cwd().createDirPath(io, options.directory);

    const resolved_file_name = blk: {
        if (options.file_name) |file_name| {
            const expected_ext = self.output_format.fileExtension();
            if (std.fs.path.extension(file_name).len == 0) {
                break :blk try std.fmt.allocPrint(self.base_allocator, "{s}.{s}", .{ file_name, expected_ext });
            }
            break :blk try self.base_allocator.dupe(u8, file_name);
        }
        break :blk try std.fmt.allocPrint(
            self.base_allocator,
            "{s}.{s}",
            .{ options.basename, self.output_format.fileExtension() },
        );
    };
    defer self.base_allocator.free(resolved_file_name);

    const path = try std.fmt.allocPrint(
        self.base_allocator,
        "{s}/{s}",
        .{ options.directory, resolved_file_name },
    );
    defer self.base_allocator.free(path);

    var buf: [65536]u8 = undefined;
    var file = try std.Io.Dir.cwd().createFile(io, path, .{ .truncate = true });
    defer file.close(io);

    var file_writer = file.writer(io, &buf);
    try self.printWithTitle(&file_writer.interface, options.title);
    try file_writer.flush();
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

fn sectionEql(a: ?[]const u8, b: ?[]const u8) bool {
    if (a == null and b == null) return true;
    if (a == null or b == null) return false;
    return std.mem.eql(u8, a.?, b.?);
}

fn writeResult(writer: *std.Io.Writer, result: BenchmarkResult, format: OutputFormat) !void {
    switch (format) {
        .plain => try writeResultPlain(writer, result),
        .markdown => try writeResultMarkdown(writer, result),
        .html => try writeResultHtml(writer, result),
    }
}

fn writePlainSectionHeader(writer: *std.Io.Writer, title: []const u8) !void {
    try writer.print("{s}\n", .{title});
}

fn writeMarkdownHeader(writer: *std.Io.Writer) !void {
    try writer.writeAll("| Benchmark | Operations | Time/op | Memory/op | Allocs/op\n");
    try writer.writeAll("|-----------|------------|---------|----------|----------|\n");
}

fn writeMarkdownSectionHeader(writer: *std.Io.Writer, title: []const u8) !void {
    try writer.print("#### {s}\n\n", .{title});
    try writeMarkdownHeader(writer);
}

fn writeHtmlDocumentHeader(writer: *std.Io.Writer, title: []const u8) !void {
    try writer.writeAll("<!DOCTYPE html>\n");
    try writer.writeAll("<html>\n");
    try writer.writeAll("<head>\n");
    try writer.print("  <title>{s}</title>\n", .{title});
    try writer.writeAll("  <style>\n");
    try writer.writeAll("    table { border-collapse: collapse; width: 100%; }\n");
    try writer.writeAll("    th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }\n");
    try writer.writeAll("    th { background-color: #4CAF50; color: white; }\n");
    try writer.writeAll("    tr:nth-child(even) { background-color: #f2f2f2; }\n");
    try writer.writeAll("  </style>\n");
    try writer.writeAll("</head>\n");
    try writer.writeAll("<body>\n");
    try writer.print("  <h1>{s}</h1>\n", .{title});
}

fn writeHtmlTableStart(writer: *std.Io.Writer) !void {
    try writer.writeAll("  <table>\n");
    try writer.writeAll("    <tr>\n");
    try writer.writeAll("      <th>Benchmark</th>\n");
    try writer.writeAll("      <th>Operations</th>\n");
    try writer.writeAll("      <th>Time/op</th>\n");
    try writer.writeAll("      <th>Memory/op</th>\n");
    try writer.writeAll("      <th>Allocs/op</th>\n");
    try writer.writeAll("    </tr>\n");
}

fn writeHtmlTableEnd(writer: *std.Io.Writer) !void {
    try writer.writeAll("  </table>\n");
}

fn writeHtmlSectionHeader(writer: *std.Io.Writer, title: []const u8) !void {
    try writer.print("  <h2>{s}</h2>\n", .{title});
    try writeHtmlTableStart(writer);
}

fn writeHtmlDocumentFooter(writer: *std.Io.Writer) !void {
    try writer.writeAll("</body>\n");
    try writer.writeAll("</html>\n");
}

fn printText(self: *const Self, writer: *std.Io.Writer, title: []const u8) !void {
    _ = title;

    if (self.results.items.len == 0) return;

    if (self.output_format == .markdown) {
        var last_section: ?[]const u8 = null;
        var wrote_header_without_section = false;

        for (self.results.items, 0..) |result, index| {
            if (!sectionEql(last_section, result.section)) {
                if (index != 0) try writer.writeAll("\n");
                if (result.section) |section| {
                    try writeMarkdownSectionHeader(writer, section);
                } else {
                    try writeMarkdownHeader(writer);
                    wrote_header_without_section = true;
                }
                last_section = result.section;
            } else if (result.section == null and !wrote_header_without_section) {
                try writeMarkdownHeader(writer);
                wrote_header_without_section = true;
            }

            try writeResult(writer, result, self.output_format);
        }
        try writer.writeAll("\n");
        return;
    }

    var last_section: ?[]const u8 = null;
    for (self.results.items, 0..) |result, index| {
        if (!sectionEql(last_section, result.section)) {
            if (index != 0) try writer.writeAll("\n");
            if (result.section) |section| {
                try writePlainSectionHeader(writer, section);
            }
            last_section = result.section;
        }
        try writeResult(writer, result, self.output_format);
    }
}

fn printHtml(self: *const Self, writer: *std.Io.Writer, title: []const u8) !void {
    try writeHtmlDocumentHeader(writer, title);

    if (self.results.items.len == 0) {
        try writeHtmlDocumentFooter(writer);
        return;
    }

    var open_table = false;
    var last_section: ?[]const u8 = null;

    for (self.results.items, 0..) |result, index| {
        if (!sectionEql(last_section, result.section)) {
            if (open_table) {
                try writeHtmlTableEnd(writer);
                try writer.writeAll("\n");
            }

            if (result.section) |section| {
                try writeHtmlSectionHeader(writer, section);
            } else {
                if (index == 0) {
                    try writeHtmlTableStart(writer);
                } else {
                    try writeHtmlTableStart(writer);
                }
            }

            open_table = true;
            last_section = result.section;
        }

        try writeResult(writer, result, self.output_format);
    }

    if (open_table) try writeHtmlTableEnd(writer);
    try writeHtmlDocumentFooter(writer);
}

fn writeResultPlain(writer: *std.Io.Writer, result: BenchmarkResult) !void {
    const time = formatTime(result.avg_ns);
    const mem_size = mem.utils.byteSize(result.avg_bytes);

    try writer.print("{s}\n", .{result.name});
    try writer.print("ops: {d:>8} {d:>9.3} {s}/op {f}/op {d}/op\n", .{
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

fn writeResultMarkdown(writer: *std.Io.Writer, result: BenchmarkResult) !void {
    const time = formatTime(result.avg_ns);
    const mem_size = mem.utils.byteSize(result.avg_bytes);

    try writer.print("| {s} | {d} | {d:.3} {s}/op | {f}/op | {d}/op |\n", .{
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

fn writeResultHtml(writer: *std.Io.Writer, result: BenchmarkResult) !void {
    const time = formatTime(result.avg_ns);
    const mem_size = mem.utils.byteSize(result.avg_bytes);

    try writer.writeAll("    <tr>\n");
    try writer.print("      <td>{s}</td>\n", .{result.name});
    try writer.print("      <td>{d}</td>\n", .{result.ops_per_iter});
    try writer.print("      <td>{d:.3} {s}/op</td>\n", .{ time.value, time.unit });
    try writer.print("      <td>{f}/op</td>\n", .{mem_size});
    try writer.print("      <td>{d}/op</td>\n", .{result.allocs_per_op});
    try writer.writeAll("    </tr>\n");
}

fn printResultPlain(result: BenchmarkResult) void {
    const time = formatTime(result.avg_ns);
    const mem_size = mem.utils.byteSize(result.avg_bytes);

    std.debug.print("{s}\n", .{result.name});
    std.debug.print("ops: {d:>8} {d:>9.3} {s}/op {f}/op {d}/op\n", .{
        result.ops_per_iter,
        time.value,
        time.unit,
        mem_size,
        result.allocs_per_op,
    });
}

fn printResultMarkdown(result: BenchmarkResult) void {
    const time = formatTime(result.avg_ns);
    const mem_size = mem.utils.byteSize(result.avg_bytes);

    std.debug.print("| {s} | {d} | {d:.3} {s}/op | {f}/op | {d}/op |\n", .{
        result.name,
        result.ops_per_iter,
        time.value,
        time.unit,
        mem_size,
        result.allocs_per_op,
    });
}

fn printResultHtml(result: BenchmarkResult) void {
    const time = formatTime(result.avg_ns);
    const mem_size = mem.utils.byteSize(result.avg_bytes);

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

test "Benchmark.run preserves operation count while sampling timing" {
    var bench = Self.init(std.testing.allocator, .plain);
    defer bench.deinit();

    var counter: usize = 0;
    const result = try bench.run("counter", 7, struct {
        fn increment(value: *usize) void {
            value.* += 1;
        }
    }.increment, .{&counter});

    try std.testing.expectEqual(@as(usize, 7), counter);
    try std.testing.expectEqual(@as(usize, 7), result.ops_per_iter);
    try std.testing.expectEqual(@as(usize, 5), result.iterations);
}
