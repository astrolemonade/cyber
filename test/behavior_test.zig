const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const stdx = @import("stdx");
const fatal = cy.fatal;
const t = stdx.testing;
const zeroInit = std.mem.zeroInit;

const cy = @import("../src/cyber.zig");
const cli = @import("../src/cli.zig");
const bt = cy.types.BuiltinTypes;
const vmc = cy.vmc;
const http = @import("../src/http.zig");
const bindings = @import("../src/builtins/bindings.zig");
const log = cy.log.scoped(.behavior_test);
const c = @import("../src/capi.zig");
comptime {
    const lib = @import("../src/lib.zig");
    std.testing.refAllDecls(lib);
}
const setup = @import("setup.zig");
const eval = setup.eval;
const compile = setup.compile;
const evalPass = setup.evalPass;
const VMrunner = setup.VMrunner;
const Config = setup.Config;
const eqUserError = setup.eqUserError;
const EvalResult = setup.EvalResult;

const Case = struct {
    config: ?Config,
    path: []const u8,
};

const Runner = struct {
    cases: std.ArrayListUnmanaged(Case),

    fn case(s: *Runner, path: []const u8) void {
        s.case2(null, path);
    }

    fn case2(s: *Runner, config: ?Config, path: []const u8) void {
        s.cases.append(t.alloc, Case{ .config = config, .path = path }) catch @panic("error");
    }
};

const caseFilter: ?[]const u8 = null;
const failFast: bool = true;

// TODO: This could be split into compiler only tests and backend tests.
//       Compiler tests would only need to be run once.
//       Right now we just run everything again since it's not that much.
test "Tests." {
    var run = Runner{ .cases = .{} };
    defer run.cases.deinit(t.alloc);

    const backend = cy.Backend.fromTestBackend(build_options.testBackend);
    const aot = backend.isAot();

    run.case("syntax/adjacent_stmt_error.cy");
    run.case("syntax/block_no_stmt_error.cy");
    run.case("syntax/change_to_spaces_error.cy");
    run.case("syntax/change_to_tabs_error.cy");
    run.case("syntax/comment_first_line.cy");
    run.case("syntax/comment_last_line.cy");
    run.case("syntax/comment_multiple.cy");
    run.case("syntax/compact_block_error.cy");
if (!aot) {
    run.case("syntax/indentation.cy");
}
    run.case("syntax/last_line_empty_indent.cy");
    run.case("syntax/no_stmts.cy");
    run.case("syntax/object_decl_eof.cy");
    run.case("syntax/object_decl_typespec_eof.cy");
    run.case("syntax/object_missing_semicolon_error.cy");
    run.case("syntax/parse_end_error.cy");
    run.case("syntax/parse_middle_error.cy");
    run.case("syntax/parse_skip_shebang_error.cy");
if (!aot) {
    run.case("syntax/parse_skip_shebang_panic.cy");
    run.case("syntax/parse_start_error.cy");
    run.case("syntax/skip_utf8_bom.cy");
    run.case("syntax/stmt_end_error.cy");
    run.case("syntax/tabs_spaces_error.cy");
    run.case("syntax/wrap_stmts.cy");

    run.case("functions/assign_capture_local_error.cy");
    run.case("functions/assign_panic.cy");
}
    run.case("functions/call_bool_param_error.cy");
if (!aot) {
    run.case("functions/call_closure.cy");
    run.case("functions/call_closure_param_panic.cy");
}
    run.case("functions/call_excess_args_error.cy");
    run.case("functions/call_excess_args_overloaded_error.cy");
if (!aot) {
    run.case("functions/call_fiber_param.cy");
}
    run.case("functions/call_fiber_param_error.cy");
    run.case("functions/call_float_param_error.cy");
if (!aot) {
    run.case("functions/call_lambda.cy");
    run.case("functions/call_lambda_incompat_arg_panic.cy");
}
    run.case("functions/call_list_param_error.cy");
    run.case("functions/call_map_param_error.cy");
if (!aot) {
    run.case("functions/call_metatype_param.cy");
}
    run.case("functions/call_metatype_param_error.cy");
    run.case("functions/call_method_missing_error.cy");
if (!aot) {
    run.case("functions/call_method_missing_panic.cy");
}
    run.case("functions/call_method_sig_error.cy");
if (!aot) {
    run.case("functions/call_method_sig_panic.cy");
    run.case("functions/call_host.cy");
    run.case("functions/call_host_param_panic.cy");
}
    run.case("functions/call_none_param_error.cy");
if (!aot) {
    run.case("functions/call_object_param.cy");
}
    run.case("functions/call_object_param_error.cy");
if (!aot) {
    run.case("functions/call_op.cy");
    run.case("functions/call_param_panic.cy");
}
    run.case("functions/call_pointer_param_error.cy");
    run.case("functions/call_recursive.cy");
if (!aot) {
    run.case("functions/call_recursive_dyn.cy");
    run.case("functions/call_static_lambda_incompat_arg_panic.cy");
    run.case("functions/call_string_param_error.cy");
    run.case("functions/call_symbol_param_error.cy");
    run.case("functions/call_typed_param.cy");
    run.case("functions/call_undeclared_error.cy");   
    run.case("functions/declare_over_builtin.cy");
    run.case("functions/method_self_param_error.cy");
    run.case("functions/object_funcs.cy");
    run.case("functions/overload.cy");
    run.case("functions/read_capture_local_error.cy");
    run.case("functions/static.cy");

    run.case("memory/arc_cases.cy");
    run.case("memory/gc_reference_cycle_unreachable.cy");
    run.case2(.{ .cleanupGC = true }, "memory/gc_reference_cycle_reachable.cy");
    run.case("memory/release_expr_stmt_return.cy");
    run.case("memory/release_scope_end.cy");

    run.case("types/cast.cy");
    run.case("types/cast_error.cy");
    run.case("types/cast_narrow_panic.cy");
    run.case("types/cast_panic.cy");
    // try case("types/cast_union_panic.cy")
    // // Failed to cast to abstract type at runtime.
    // try eval(.{ .silent = true },
    //     \\my a = 123
    //     \\print(a as String)
    // , struct { fn func(run: *VMrunner, res: EvalResult) !void {
    //     try run.expectErrorReport(res, error.Panic,
    //         \\panic: Can not cast `int` to `String`.
    //         \\
    //         \\main:2:9 main:
    //         \\print(a as String)
    //         \\        ^
    //         \\
    //     );
    // }}.func);
    run.case("types/choice_access_error.cy");
    run.case("types/choice_hidden_fields.cy");
    run.case("types/choice_type.cy");
}
    run.case("types/dyn_recent_type_error.cy");
if (!aot) {
    run.case("types/enums.cy");
}
    run.case("types/func_return_type_error.cy");
    run.case("types/func_param_type_undeclared_error.cy");
if (!aot) {
    run.case("types/object_init_dyn_field.cy");
    run.case("types/object_init_field.cy");
    run.case("types/object_init_field_error.cy");
    run.case("types/object_init_field_panic.cy");
    run.case("types/object_init_undeclared_field_error.cy");
    run.case("types/object_set_field.cy");
    run.case("types/object_set_field_dyn_recv_panic.cy");
    run.case("types/object_set_field_error.cy");
    run.case("types/object_set_field_panic.cy");
    run.case("types/object_set_undeclared_field_error.cy");
    run.case("types/object_zero_init.cy");
    run.case("types/object_zero_init_error.cy");
    run.case("types/objects.cy");
    run.case("types/type_alias.cy");
    run.case("types/type_spec.cy");
    run.case("types/unnamed_object.cy");

    if (!cy.isWasm) {
        run.case2(Config.initFileModules("./test/modules/type_spec.cy"), "modules/type_spec.cy");
        run.case2(Config.initFileModules("./test/modules/type_alias.cy"), "modules/type_alias.cy");
        run.case2(Config.initFileModules("./test/modules/import_not_found_error.cy").withSilent(), "modules/import_not_found_error.cy");
        run.case2(Config.initFileModules("./test/modules/import_missing_sym_error.cy").withSilent(), "modules/import_missing_sym_error.cy");
        run.case2(Config.initFileModules("./test/modules/import_rel_path.cy"), "modules/import_rel_path.cy");
        run.case2(Config.initFileModules("./test/modules/import_implied_rel_path.cy"), "modules/import_implied_rel_path.cy");
        run.case2(Config.initFileModules("./test/modules/import_unresolved_rel_path.cy"), "modules/import_unresolved_rel_path.cy");
        
        // Import when running main script in the cwd.
        run.case2(Config.initFileModules("./import_rel_path.cy").withChdir("./test/modules"), "modules/import_rel_path.cy");
        // Import when running main script in a child directory.
        run.case2(Config.initFileModules("../import_rel_path.cy").withChdir("./test/modules/test_mods"), "modules/import_rel_path.cy");

        run.case2(Config.initFileModules("./test/modules/import.cy"), "modules/import.cy");
    }
    run.case("modules/core.cy");
    run.case("modules/math.cy");
    run.case("modules/test_eq_panic.cy");
    run.case("modules/test.cy");
    if (!cy.isWasm) {
        run.case("modules/os.cy");
    }

    run.case2(.{ .silent = true }, "meta/dump_locals.cy");
    run.case("meta/metatype.cy");

    run.case("concurrency/fibers.cy");

    run.case("errors/error_values.cy");
    run.case("errors/throw.cy");
    run.case("errors/throw_func_panic.cy");
    run.case("errors/throw_main_panic.cy");
    run.case("errors/throw_nested_func_panic.cy");
    run.case("errors/try_catch.cy");
    run.case("errors/try_catch_expr.cy");
    run.case("errors/try_expr.cy");

    run.case("builtins/arithmetic_ops.cy");
    run.case("builtins/arithmetic_unsupported_panic.cy");
    run.case("builtins/arrays.cy");
    run.case("builtins/array_slices.cy");
    run.case("builtins/bitwise_ops.cy");
    run.case("builtins/bools.cy");
    run.case("builtins/compare_eq.cy");
    run.case("builtins/compare_neq.cy");
    run.case("builtins/compare_numbers.cy");
    run.case("builtins/dynamic_ops.cy");
    run.case("builtins/escape_sequences.cy");
    run.case("builtins/floats.cy");
    run.case("builtins/ints.cy");
    run.case("builtins/int_unsupported_notation_error.cy");
    run.case("builtins/list_neg_index_oob_panic.cy");
    run.case("builtins/lists.cy");
    run.case("builtins/logic_ops.cy");
    run.case("builtins/maps.cy");
    run.case("builtins/must.cy");
    run.case("builtins/must_panic.cy");
    run.case("builtins/optionals.cy");
    run.case("builtins/op_precedence.cy");
    run.case("builtins/panic_panic.cy");
    run.case("builtins/raw_string_single_quote_error.cy");
    run.case("builtins/raw_string_new_line_error.cy");
    run.case("builtins/rune_empty_lit_error.cy");
    run.case("builtins/rune_multiple_lit_error.cy");
    run.case("builtins/rune_grapheme_cluster_lit_error.cy");
    run.case("builtins/set_index_unsupported_panic.cy");
    run.case("builtins/string_new_line_error.cy");
    run.case("builtins/string_interpolation.cy");
    run.case("builtins/strings.cy");
    run.case("builtins/strings_ascii.cy");
    run.case("builtins/strings_utf8.cy");
    run.case("builtins/string_slices_ascii.cy");
    run.case("builtins/string_slices_utf8.cy");
    run.case("builtins/symbols.cy");
    run.case("builtins/truthy.cy");
}

    run.case("vars/local_annotate_error.cy");
    run.case("vars/local_assign_error.cy");
if (!aot) {
    run.case("vars/local_assign.cy");
}
    run.case("vars/local_dup_captured_error.cy");
    run.case("vars/local_dup_error.cy");
    run.case("vars/local_dup_static_error.cy");
    run.case("vars/local_init_error.cy");
if (!aot) {
    run.case("vars/local_init.cy");
    run.case("vars/op_assign.cy");
}
    run.case("vars/read_undeclared_error.cy");
    run.case("vars/read_undeclared_error.cy");
    run.case("vars/read_undeclared_diff_scope_error.cy");
    run.case("vars/read_outside_if_var_error.cy");
    run.case("vars/read_outside_for_iter_error.cy");
    run.case("vars/read_outside_for_var_error.cy");
    run.case("vars/set_undeclared_error.cy");
if (!aot) {
    run.case("vars/static_assign.cy");
    run.case("vars/static_init.cy");
}
    run.case("vars/static_init_capture_error.cy");
    run.case("vars/static_init_circular_ref_error.cy");
if (!aot) {
    run.case("vars/static_init_dependencies.cy");
    run.case("vars/static_init_error.cy");
    run.case("vars/static_init_read_self_error.cy");

    run.case("control_flow/cond_expr.cy");
    run.case("control_flow/for_iter.cy");
    run.case("control_flow/for_iter_unsupported_panic.cy");
    run.case("control_flow/for_range.cy");
    run.case("control_flow/if_stmt.cy");
    run.case("control_flow/switch.cy");
    run.case("control_flow/return.cy");
    run.case("control_flow/while_cond.cy");
    run.case("control_flow/while_inf.cy");
    run.case("control_flow/while_unwrap_opt.cy");
}

    var numPassed: u32 = 0;
    for (run.cases.items) |run_case| {
        if (caseFilter) |filter| {
            if (std.mem.indexOf(u8, run_case.path, filter) == null) {
                continue;
            }
        }
        std.debug.print("test: {s}\n", .{run_case.path});
        case2(run_case.config, run_case.path) catch |err| {
            std.debug.print("Failed: {}\n", .{err});
            if (failFast) {
                return err;
            } else {
                continue;
            }
        };
        numPassed += 1;
    }
    std.debug.print("Tests: {}/{}\n", .{numPassed, run.cases.items.len});
    if (numPassed < run.cases.items.len) {
        return error.Failed;
    }
}

test "Compile." {
    // examples.
    try compileCase(.{}, "../examples/fiber.cy");
    try compileCase(.{}, "../examples/fizzbuzz.cy");
    try compileCase(.{}, "../examples/hello.cy");
    try compileCase(.{}, "../examples/ffi.cy");
    try compileCase(.{}, "../examples/account.cy");
    try compileCase(.{}, "../examples/fibonacci.cy");

    // tools.
    try compileCase(.{}, "../src/tools/bench.cy");
    try compileCase(.{}, "../src/tools/llvm.cy");
    try compileCase(.{}, "../src/tools/clang_bs.cy");
    try compileCase(.{}, "../src/tools/md4c.cy");
    if (!cy.isWasm) {
        try compileCase(Config.initFileModules("./src/tools/cbindgen.cy"), "../src/tools/cbindgen.cy");
        try compileCase(Config.initFileModules("./docs/gen-docs.cy"), "../docs/gen-docs.cy");
        try compileCase(Config.initFileModules("./src/jit/gen-stencils-a64.cy"), "../src/jit/gen-stencils-a64.cy");
        try compileCase(Config.initFileModules("./src/jit/gen-stencils-x64.cy"), "../src/jit/gen-stencils-x64.cy");
    }

    // benchmarks.
    try compileCase(.{}, "bench/fib/fib.cy");
    try compileCase(.{}, "bench/fiber/fiber.cy");
    try compileCase(.{}, "bench/for/for.cy");
    try compileCase(.{}, "bench/heap/heap.cy");
    try compileCase(.{}, "bench/string/index.cy");
}

fn compileCase(config: Config, path: []const u8) !void {
    const fpath = try std.mem.concat(t.alloc, u8, &.{ thisDir(), "/", path });
    defer t.alloc.free(fpath);
    const contents = try std.fs.cwd().readFileAlloc(t.alloc, fpath, 1e9);
    defer t.alloc.free(contents);
    try compile(config, contents);
}

test "Custom modules." {
    const run = VMrunner.create();
    defer run.destroy();

    var count: usize = 0;
    c.setUserData(@ptrCast(run.vm), &count);

    c.setResolver(@ptrCast(run.vm), cy.vm_compiler.defaultModuleResolver);
    const S = struct {
        fn test1(vm: *cy.VM, _: [*]const cy.Value, _: u8) cy.Value {
            const count_ = cy.ptrAlignCast(*usize, vm.userData);
            count_.* += 1;
            return cy.Value.None;
        }
        fn test2(vm: *cy.VM, _: [*]const cy.Value, _: u8) cy.Value {
            const count_ = cy.ptrAlignCast(*usize, vm.userData);
            count_.* += 2;
            return cy.Value.None;
        }
        fn test3(vm: *cy.VM, _: [*]const cy.Value, _: u8) cy.Value {
            const count_ = cy.ptrAlignCast(*usize, vm.userData);
            count_.* += 3;
            return cy.Value.None;
        }
        fn postLoadMod2(_: ?*c.VM, mod: c.ApiModule) callconv(.C) void {
            // Test dangling pointer.
            const s1 = allocString("test\x00");
            defer t.alloc.free(s1);
            c.declareUntypedFunc(mod, s1.ptr, 0, @ptrCast(&test3));
        }
        fn postLoadMod1(_: ?*c.VM, mod: c.ApiModule) callconv(.C) void {
            // Test dangling pointer.
            const s1 = allocString("test\x00");
            const s2 = allocString("test2\x00");
            defer t.alloc.free(s1);
            defer t.alloc.free(s2);

            c.declareUntypedFunc(mod, s1.ptr, 0, @ptrCast(&test1));
            c.declareUntypedFunc(mod, s2.ptr, 0, @ptrCast(&test2));
        }
        fn loader(vm_: ?*c.VM, spec: c.Str, out_: [*c]c.ModuleLoaderResult) callconv(.C) bool {
            const out: *c.ModuleLoaderResult = out_;

            const name = c.strSlice(spec);
            if (std.mem.eql(u8, name, "builtins")) {
                const defaultLoader = cy.vm_compiler.defaultModuleLoader;
                return defaultLoader(vm_, spec, @ptrCast(out));
            }
            if (std.mem.eql(u8, name, "mod1")) {
                out.* = zeroInit(c.ModuleLoaderResult, .{
                    .src = "",
                    .onLoad = &postLoadMod1,
                });
                return true;
            } else if (std.mem.eql(u8, name, "mod2")) {
                out.* = zeroInit(c.ModuleLoaderResult, .{
                    .src = "",
                    .onLoad = &postLoadMod2,
                });
                return true;
            }
            return false;
        }
    };
    c.setModuleLoader(@ptrCast(run.vm), @ptrCast(&S.loader));

    const src1 = try t.alloc.dupe(u8, 
        \\import m 'mod1'
        \\import n 'mod2'
        \\m.test()
        \\m.test2()
        \\n.test()
    );
    _ = try run.evalExtNoReset(.{}, src1);

    // Test dangling pointer.
    t.alloc.free(src1);

    _ = try run.evalExtNoReset(.{},
        \\import m 'mod1'
        \\import n 'mod2'
        \\m.test()
        \\m.test2()
        \\n.test()
    );

    try t.eq(count, 12);
}

fn allocString(str: []const u8) []const u8 {
    return t.alloc.dupe(u8, str) catch @panic("");
}

test "Multiple evals persisting state." {
    const run = VMrunner.create();
    defer run.destroy();

    var global = run.vm.allocEmptyMap() catch fatal();
    defer run.vm.release(global);
    c.setUserData(@ptrCast(run.vm), &global);

    c.setResolver(@ptrCast(run.vm), cy.vm_compiler.defaultModuleResolver);
    c.setModuleLoader(@ptrCast(run.vm), struct {
        fn onLoad(vm_: ?*c.VM, mod: c.ApiModule) callconv(.C) void {
            const vm: *cy.VM = @ptrCast(@alignCast(vm_));
            const sym: *cy.Sym = @ptrCast(@alignCast(mod.sym));
            const g = cy.ptrAlignCast(*cy.Value, vm.userData).*;
            const chunk = sym.getMod().?.chunk;
            _ = chunk.declareHostVar(sym, "g", cy.NullId, bt.Dynamic, g) catch fatal();
        }
        fn loader(vm: ?*c.VM, spec: c.Str, out_: [*c]c.ModuleLoaderResult) callconv(.C) bool {
            const out: *c.ModuleLoaderResult = out_;
            if (std.mem.eql(u8, c.strSlice(spec), "mod")) {
                out.* = zeroInit(c.ModuleLoaderResult, .{
                    .src = "",
                    .onLoad = onLoad,
                });
                return true;
            } else {
                return cli.loader(vm, spec, out);
            }
        }
    }.loader);

    const src1 =
        \\import m 'mod'
        \\m.g['a'] = 1
        ;
    _ = try run.vm.eval("main", src1, .{ 
        .singleRun = false,
        .enableFileModules = false,
        .genAllDebugSyms = false,
    });

    const src2 = 
        \\import m 'mod'
        \\import t 'test'
        \\t.eq(m.g['a'], 1)
        ;
    _ = try run.vm.eval("main", src2, .{ 
        .singleRun = false,
        .enableFileModules = false,
        .genAllDebugSyms = false,
    });
}

test "Multiple evals with same VM." {
    const run = VMrunner.create();
    defer run.destroy();

    const src =
        \\import t 'test'
        \\var a = 1
        \\t.eq(a, 1)
        ;

    _ = try run.vm.eval("main", src, .{ 
        .singleRun = false,
        .enableFileModules = false,
        .genAllDebugSyms = false,
    });
    _ = try run.vm.eval("main", src, .{ 
        .singleRun = false,
        .enableFileModules = false,
        .genAllDebugSyms = false,
    });
    _ = try run.vm.eval("main", src, .{ 
        .singleRun = false,
        .enableFileModules = false,
        .genAllDebugSyms = false,
    });
}

test "Debug labels." {
    try eval(.{},
        \\var a = 1
        \\#genLabel('MyLabel')
        \\a = 1
    , struct { fn func(run: *VMrunner, res: EvalResult) !void {
        _ = try res;
        const vm = run.vm;
        for (vm.compiler.buf.debugMarkers.items) |marker| {
            if (marker.pc == 3) {
                try t.eqStr(marker.getLabelName(), "MyLabel");
                return;
            }
        }
        try t.fail();
    }}.func);
}

test "Import http spec." {
    if (cy.isWasm) {
        return;
    }

    const run = VMrunner.create();
    defer run.destroy();

    const basePath = try std.fs.realpathAlloc(t.alloc, ".");
    defer t.alloc.free(basePath);

    // Import error.UnknownHostName.
    try run.resetEnv();
    var client = http.MockHttpClient.init(t.alloc);
    client.retReqError = error.UnknownHostName;
    run.vm.httpClient = client.iface();
    var res = run.evalExtNoReset(Config.initFileModules("./test/modules/import.cy").withSilent(),
        \\import a 'https://doesnotexist123.com/'
        \\b = a
    );
    try t.expectError(res, error.CompileError);
    var err = try cy.debug.allocLastUserCompileError(run.vm);
    try eqUserError(t.alloc, err,
        \\CompileError: Can not connect to `doesnotexist123.com`.
        \\
        \\@AbsPath(test/modules/import.cy):1:11:
        \\import a 'https://doesnotexist123.com/'
        \\          ^
        \\
    );

    // Import NotFound response code.
    try run.resetEnv();
    client = http.MockHttpClient.init(t.alloc);
    client.retStatusCode = std.http.Status.not_found;
    run.vm.httpClient = client.iface();
    res = run.evalExtNoReset(Config.initFileModules("./test/modules/import.cy").withSilent(),
        \\import a 'https://exists.com/missing'
        \\b = a
    );
    try t.expectError(res, error.CompileError);
    err = try cy.debug.allocLastUserCompileError(run.vm);
    try eqUserError(t.alloc, err,
        \\CompileError: Can not load `https://exists.com/missing`. Response code: not_found
        \\
        \\@AbsPath(test/modules/import.cy):1:11:
        \\import a 'https://exists.com/missing'
        \\          ^
        \\
    );

    // Successful import.
    try run.resetEnv();
    client = http.MockHttpClient.init(t.alloc);
    client.retBody =
        \\var .foo = 123
        ;
    run.vm.httpClient = client.iface();
    _ = try run.evalExtNoReset(Config.initFileModules("./test/modules/import.cy"),
        \\import a 'https://exists.com/a.cy'
        \\import t 'test'
        \\t.eq(a.foo, 123)
    );
}

test "os constants" {
    try eval(.{},
        \\import os
        \\os.system
    , struct { fn func(run: *VMrunner, res: EvalResult) !void {
        const val = try res;
        try t.eqStr(try run.assertValueString(val), @tagName(builtin.os.tag));
        run.vm.release(val);
    }}.func);

    try eval(.{},
        \\import os
        \\os.cpu
    , struct { fn func(run: *VMrunner, res: EvalResult) !void {
        const val = try res;
        try t.eqStr(try run.assertValueString(val), @tagName(builtin.cpu.arch));
        run.vm.release(val);
    }}.func);

    try eval(.{},
        \\import os
        \\os.endian
    , struct { fn func(run: *VMrunner, res: EvalResult) !void {
        const val = try res;
        if (builtin.cpu.arch.endian() == .Little) {
            try t.eq(val.asSymbolId(), @intFromEnum(bindings.Symbol.little));
        } else {
            try t.eq(val.asSymbolId(), @intFromEnum(bindings.Symbol.big));
        }
        run.vm.release(val);
    }}.func);
}

test "FFI." {
    if (cy.isWasm) {
        return;
    }
    const S = struct {
        export fn testAdd(a: i32, b: i32) i32 {
            return a + b;
        }
        export fn testI8(n: i8) i8 {
            return n;
        }
        export fn testU8(n: u8) u8 {
            return n;
        }
        export fn testI16(n: i16) i16 {
            return n;
        }
        export fn testU16(n: u16) u16 {
            return n;
        }
        export fn testI32(n: i32) i32 {
            return n;
        }
        export fn testU32(n: u32) u32 {
            return n;
        }
        export fn testI64(n: i64) i64 {
            return n;
        }
        export fn testU64(n: u64) u64 {
            return n;
        }
        export fn testUSize(n: usize) usize {
            return n;
        }
        export fn testF32(n: f32) f32 {
            return n;
        }
        export fn testF64(n: f64) f64 {
            return n;
        }
        export fn testCharPtr(ptr: [*:0]u8) [*:0]const u8 {
            return ptr;
        }
        export fn testVoidPtr(ptr: *anyopaque) *anyopaque {
            return ptr;
        }
        export fn testVoid() void {
        }
        export fn testBool(b: bool) bool {
            return b;
        }
        const MyObject = extern struct {
            a: f64,
            b: i32,
            c: [*:0]u8,
            d: bool,
        };
        export fn testObject(o: MyObject) MyObject {
            return MyObject{
                .a = o.a,
                .b = o.b,
                .c = o.c,
                .d = o.d,
            };
        }
        export fn testRetObjectPtr(o: MyObject) *MyObject {
            temp = .{
                .a = o.a,
                .b = o.b,
                .c = o.c,
                .d = o.d,
            };
            return &temp;
        }
        export fn testArray(arr: [*c]f64) f64 {
            return arr[0] + arr[1];
        }

        export fn testCallback(a: i32, b: i32, add: *const fn (i32, i32) callconv(.C) i32) i32 {
            return add(a, b);
        }

        var temp: MyObject = undefined;
    };
    _ = S;

    try case("ffi/call_incompat_arg_panic.cy");
    try case("ffi/call_excess_args_panic.cy");

    // TODO: Test callback failure and verify stack trace.
    // Currently, the VM aborts when encountering a callback error.
    // A config could be added to make the initial FFI call detect an error and throw a panic instead.

    try case("ffi/ffi.cy");
}

test "object_init_dyn_field_gen" {
    // Initialize field with dynamic/typed value does not gen `objectTypeCheck`.
    try eval(.{ .silent = true },
        \\type S:
        \\  my a
        \\func foo():
        \\  return 123
        \\var s = [S a: foo()]
        \\var t = [S a: 123]
    , struct { fn func(run: *VMrunner, res: EvalResult) !void {
        _ = try res;

        const ops = run.vm.ops;
        var pc: u32 = 0;
        while (pc < ops.len) {
            if (@as(cy.OpCode, @enumFromInt(ops[pc].val)) == .objectTypeCheck) {
                return error.Failed;
            }
            pc += cy.bytecode.getInstLenAt(ops.ptr + pc);
        }
    }}.func);
}

test "windows new lines" {
    try eval(.{ .silent = true }, "a = 123\r\nb = 234\r\nc =",
    struct { fn func(run: *VMrunner, res: EvalResult) !void {
        try run.expectErrorReport(res, error.ParseError,
            \\ParseError: Expected expression.
            \\
            \\main:3:4:
            \\c =
            \\   ^
            \\
        );
    }}.func);
}

test "Stack trace unwinding." {
    const run = VMrunner.create();
    defer run.destroy();

    var res = run.evalExt(.{ .silent = true },
        \\import test
        \\my a = test.erase(123)
        \\1 + a.foo
    );
    try run.expectErrorReport(res, error.Panic,
        \\panic: Field not found in value.
        \\
        \\main:3:7 main:
        \\1 + a.foo
        \\      ^
        \\
    );
    var trace = run.getStackTrace();
    try t.eq(trace.frames.len, 1);
    try eqStackFrame(trace.frames[0], .{
        .name = "main",
        .chunkId = 0,
        .line = 2,
        .col = 6,
        .lineStartPos = 35,
    });

    // Function stack trace.
    res = run.evalExt(.{ .silent = true },
        \\import test
        \\func foo():
        \\  my a = test.erase(123)
        \\  return 1 + a.foo
        \\foo()
    );
    try run.expectErrorReport(res, error.Panic,
        \\panic: Field not found in value.
        \\
        \\main:4:16 foo:
        \\  return 1 + a.foo
        \\               ^
        \\main:5:1 main:
        \\foo()
        \\^
        \\
    );
    trace = run.getStackTrace();
    try t.eq(trace.frames.len, 2);
    try eqStackFrame(trace.frames[0], .{
        .name = "foo",
        .chunkId = 0,
        .line = 3,
        .col = 15,
        .lineStartPos = 49,
    });
    try eqStackFrame(trace.frames[1], .{
        .name = "main",
        .chunkId = 0,
        .line = 4,
        .col = 0,
        .lineStartPos = 68,
    });

    if (!cy.isWasm) {
    
        // panic from another module.
        res = run.evalExt(.{ .silent = true, .uri = "./test/main.cy" },
            \\import a 'modules/test_mods/init_panic_error.cy'
            \\import t 'test'
            \\t.eq(a.foo, 123)
        );
        try t.expectError(res, error.Panic);
        trace = run.getStackTrace();
        try t.eq(trace.frames.len, 2);
        try eqStackFrame(trace.frames[0], .{
            .name = "init",
            .chunkId = 2,
            .line = 0,
            .col = 11,
            .lineStartPos = 0,
        });
        try eqStackFrame(trace.frames[1], .{
            .name = "main",
            .chunkId = 0,
            .line = 0,
            .col = 0,
            .lineStartPos = cy.NullId,
        });

        run.deinit();

        // `throw` from another module's var initializer.
        try eval(.{ .silent = true, .uri = "./test/main.cy" },
            \\import a 'modules/test_mods/init_throw_error.cy'
            \\import t 'test'
            \\t.eq(a.foo, 123)
        , struct { fn func(run_: *VMrunner, res_: EvalResult) !void {
            try run_.expectErrorReport(res_, error.Panic,
                \\panic: error.boom
                \\
                \\@AbsPath(test/modules/test_mods/init_throw_error.cy):1:12 init:
                \\var .foo = throw error.boom
                \\           ^
                \\./test/main.cy: main
                \\
            );
            const trace_ = run_.getStackTrace();
            try t.eq(trace_.frames.len, 2);
            try eqStackFrame(trace_.frames[0], .{
                .name = "init",
                .chunkId = 2,
                .line = 0,
                .col = 11,
                .lineStartPos = 0,
            });
            try eqStackFrame(trace_.frames[1], .{
                .name = "main",
                .chunkId = 0,
                .line = 0,
                .col = 0,
                .lineStartPos = cy.NullId,
            });
        }}.func);
    }
}

fn eqStackFrame(act: cy.StackFrame, exp: cy.StackFrame) !void {
    try t.eqStr(act.name, exp.name);
    try t.eq(act.chunkId, exp.chunkId);
    try t.eq(act.line, exp.line);
    try t.eq(act.col, exp.col);
    try t.eq(act.lineStartPos, exp.lineStartPos);
}

// test "Function named parameters call." {
//     const run = VMrunner.create();
//     defer run.destroy();

//     var val = try run.eval(
//         \\func foo(a, b):
//         \\  return a - b
//         \\foo(a: 3, b: 1)
//     );
//     try t.eq(val.asF64toI32(), 2);
//     run.deinitValue(val);

//     val = try run.eval(
//         \\func foo(a, b):
//         \\  return a - b
//         \\foo(a: 1, b: 3)
//     );
//     try t.eq(val.asF64toI32(), -2);
//     run.deinitValue(val);

//     // New line as arg separation.
//     val = try run.eval(
//         \\func foo(a, b):
//         \\  return a - b
//         \\foo(
//         \\  a: 3
//         \\  b: 1
//         \\)
//     );
//     try t.eq(val.asF64toI32(), 2);
//     run.deinitValue(val);
// }

// test "@name" {
//     const run = VMrunner.create();
//     defer run.destroy();

//     const parse_res = try run.parse(
//         \\@name foo
//     );
//     try t.eqStr(parse_res.name, "foo");

//     if (build_options.cyEngine == .qjs) {
//         // Compile step skips the statement.
//         const compile_res = try run.compile(
//             \\@name foo
//         );
//         try t.eqStr(compile_res.output, "(function () {});");
//     }
// }

// test "implicit await" {
//     const run = VMrunner.create();
//     defer run.destroy();

//     var val = try run.eval(
//         \\func foo() apromise:
//         \\  task = @asyncTask()
//         \\  @queueTask(func () => task.resolve(123))
//         \\  return task.promise
//         \\1 + foo()
//     );
//     try t.eq(val.asF64toI32(), 124);
//     run.deinitValue(val);
// }

// test "await" {
//     const run = VMrunner.create();
//     defer run.destroy();

//     var val = try run.eval(
//         \\func foo():
//         \\  task = @asyncTask()
//         \\  @queueTask(func () => task.resolve(123))
//         \\  return task.promise
//         \\await foo()
//     );
//     try t.eq(val.asF64toI32(), 123);
//     run.deinitValue(val);

//     // await on value.
//     val = try run.eval(
//         \\func foo():
//         \\  return 234
//         \\await foo()
//     );
//     try t.eq(val.asF64toI32(), 234);
//     run.deinitValue(val);
// }

test "Return from main." {
    try eval(.{},
        \\return 123
    , struct { fn func(_: *VMrunner, res: EvalResult) !void {
        const val = try res;
        try t.eq(val.asInteger(), 123);
    }}.func);
}

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse @panic("error");
}

fn case(path: []const u8) !void {
    try case2(null, path);
}

fn case2(config: ?Config, path: []const u8) !void {
    const fpath = try std.mem.concat(t.alloc, u8, &.{ thisDir(), "/", path });
    defer t.alloc.free(fpath);
    const contents = try std.fs.cwd().readFileAlloc(t.alloc, fpath, 1e9);
    defer t.alloc.free(contents);

    var idx = std.mem.indexOf(u8, contents, "cytest:") orelse {
        return error.MissingCyTest;
    };

    var rest = contents[idx+7..];
    idx = std.mem.indexOfScalar(u8, rest, '\n') orelse rest.len;
    const test_t = std.mem.trim(u8, rest[0..idx], " ");

    if (std.mem.eql(u8, test_t, "error")) {
        // Find end of last comment.
        const start = idx+1;
        while (true) {
            if (rest[idx..].len >= 3 and rest[idx] == '\n' and rest[idx+1] == '-' and rest[idx+2] == '-') {
                idx += 1;
                if (std.mem.indexOfScalarPos(u8, rest, idx, '\n')) |nl| {
                    idx = nl;
                } else {
                    idx = rest.len;
                }
            } else {
                break;
            }
        }

        const exp = rest[start..idx];

        var buf: [1024]u8 = undefined;
        const len = std.mem.replacementSize(u8, exp, "--", "");
        _ = std.mem.replace(u8, exp, "--", "", &buf);

        const Context = struct {
            exp: []const u8,
        };
        var ctx = Context{ .exp = buf[0..len]};
        var fconfig: Config = config orelse .{ .silent = true };
        fconfig.ctx = &ctx;
        try eval(fconfig, contents
        , struct { fn func(run: *VMrunner, res: EvalResult) !void {
            var ctx_: *Context = @ptrCast(@alignCast(run.ctx));
            try run.expectErrorReport2(res, ctx_.exp);
        }}.func);
    } else if (std.mem.eql(u8, test_t, "pass")) {
        var fconfig: Config = config orelse .{};
        try evalPass(fconfig, contents);
    } else {
        return error.UnsupportedTestType;
    }
}
