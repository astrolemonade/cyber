const std = @import("std");
const stdx = @import("stdx");
const builtin = @import("builtin");
const tcc = @import("tcc");

const cy = @import("cyber.zig");
const Value = cy.Value;
const vm_ = @import("vm.zig");
const TrackGlobalRC = vm_.TrackGlobalRC;
const gvm = &vm_.gvm;
const fmt = @import("fmt.zig");

const debug = builtin.mode == .Debug;
const log = stdx.log.scoped(.bindings);

const NullId = std.math.maxInt(u32);

const TagLit_int = 0;
const TagLit_i8 = 1;
const TagLit_u8 = 2;
const TagLit_i16 = 3;
const TagLit_u16 = 4;
const TagLit_i32 = 5;
const TagLit_u32 = 6;
const TagLit_f32 = 7;
const TagLit_f64 = 8;
const TagLit_float = 9;
const TagLit_double = 10;
const TagLit_charPtrZ = 11;
const TagLit_ptr = 12;
const TagLit_AssertError = 13;
const TagLit_NotFound = 14;
const TagLit_running = 15;
const TagLit_paused = 16;
const TagLit_done = 17;
const TagLit_error = 18;
const TagLit_number = 19;
const TagLit_object = 20;
const TagLit_bool = 21;

const StdSection = ".eval.std";
const Section = ".eval2";

// This keeps .eval section first in order.
pub export fn forceSectionDep() linksection(".eval") callconv(.C) void {}

pub fn bindCore(self: *cy.VM) !void {
    @setCold(true);
    forceSectionDep();

    const resize = try self.ensureMethodSymKey("resize");
    self.iteratorObjSym = try self.ensureMethodSymKey("iterator");
    self.nextObjSym = try self.ensureMethodSymKey("next");
    self.pairIteratorObjSym = try self.ensureMethodSymKey("pairIterator");
    self.nextPairObjSym = try self.ensureMethodSymKey("nextPair");
    const add = try self.ensureMethodSymKey("add");
    const insert = try self.ensureMethodSymKey("insert");
    const remove = try self.ensureMethodSymKey("remove");
    const sort = try self.ensureMethodSymKey("sort");
    const size = try self.ensureMethodSymKey("size");
    const len = try self.ensureMethodSymKey("len");
    const charAt = try self.ensureMethodSymKey("charAt");
    const status = try self.ensureMethodSymKey("status");

    // Init compile time builtins.

    // Primitive types.
    var id = try self.addStruct("none");
    std.debug.assert(id == cy.NoneT);
    id = try self.addStruct("boolean");
    std.debug.assert(id == cy.BooleanT);
    id = try self.addStruct("error");
    std.debug.assert(id == cy.ErrorT);
    id = try self.addStruct("conststring");
    std.debug.assert(id == cy.ConstStringT);
    try self.addMethodSym(cy.ConstStringT, len, cy.SymbolEntry.initNativeFunc1(constStringLen));
    try self.addMethodSym(cy.ConstStringT, charAt, cy.SymbolEntry.initNativeFunc1(constStringCharAt));
    id = try self.addStruct("tag");
    std.debug.assert(id == cy.UserTagT);
    id = try self.addStruct("tagliteral");
    std.debug.assert(id == cy.UserTagLiteralT);
    id = try self.addStruct("integer");
    std.debug.assert(id == cy.IntegerT);
    id = try self.addStruct("number");
    std.debug.assert(id == cy.NumberT);

    id = try self.addStruct("List");
    std.debug.assert(id == cy.ListS);
    try self.addMethodSym(cy.ListS, resize, cy.SymbolEntry.initNativeFunc1(listResize));
    try self.addMethodSym(cy.ListS, self.iteratorObjSym, cy.SymbolEntry.initNativeFunc1(listIterator));
    try self.addMethodSym(cy.ListS, self.nextObjSym, cy.SymbolEntry.initNativeFunc1(listNext));
    try self.addMethodSym(cy.ListS, self.pairIteratorObjSym, cy.SymbolEntry.initNativeFunc1(listIterator));
    try self.addMethodSym(cy.ListS, self.nextPairObjSym, cy.SymbolEntry.initNativeFunc2(listNextPair));
    try self.addMethodSym(cy.ListS, add, cy.SymbolEntry.initNativeFunc1(listAdd));
    try self.addMethodSym(cy.ListS, insert, cy.SymbolEntry.initNativeFunc1(listInsert));
    try self.addMethodSym(cy.ListS, remove, cy.SymbolEntry.initNativeFunc1(listRemove));
    try self.addMethodSym(cy.ListS, sort, cy.SymbolEntry.initNativeFunc1(listSort));
    try self.addMethodSym(cy.ListS, size, cy.SymbolEntry.initNativeFunc1(listSize));

    id = try self.addStruct("Map");
    std.debug.assert(id == cy.MapS);
    try self.addMethodSym(cy.MapS, remove, cy.SymbolEntry.initNativeFunc1(mapRemove));
    try self.addMethodSym(cy.MapS, size, cy.SymbolEntry.initNativeFunc1(mapSize));
    try self.addMethodSym(cy.MapS, self.iteratorObjSym, cy.SymbolEntry.initNativeFunc1(mapIterator));
    try self.addMethodSym(cy.MapS, self.pairIteratorObjSym, cy.SymbolEntry.initNativeFunc1(mapIterator));
    try self.addMethodSym(cy.MapS, self.nextObjSym, cy.SymbolEntry.initNativeFunc1(mapNext));
    try self.addMethodSym(cy.MapS, self.nextPairObjSym, cy.SymbolEntry.initNativeFunc2(mapNextPair));

    id = try self.addStruct("Closure");
    std.debug.assert(id == cy.ClosureS);

    id = try self.addStruct("Lambda");
    std.debug.assert(id == cy.LambdaS);

    id = try self.addStruct("String");
    std.debug.assert(id == cy.StringS);
    try self.addMethodSym(cy.StringS, len, cy.SymbolEntry.initNativeFunc1(stringLen));
    try self.addMethodSym(cy.StringS, charAt, cy.SymbolEntry.initNativeFunc1(stringCharAt));

    id = try self.addStruct("Fiber");
    std.debug.assert(id == cy.FiberS);
    try self.addMethodSym(cy.FiberS, status, cy.SymbolEntry.initNativeFunc1(fiberStatus));

    id = try self.addStruct("Box");
    std.debug.assert(id == cy.BoxS);

    id = try self.addStruct("NativeFunc1");
    std.debug.assert(id == cy.NativeFunc1S);

    id = try self.addStruct("TccState");
    std.debug.assert(id == cy.TccStateS);

    id = try self.addStruct("OpaquePtr");
    std.debug.assert(id == cy.OpaquePtrS);

    const sid = try self.ensureStruct("CFunc");
    self.structs.buf[sid].numFields = 3;
    id = try self.ensureFieldSym("sym");
    try self.addFieldSym(sid, id, 0);
    id = try self.ensureFieldSym("args");
    try self.addFieldSym(sid, id, 1);
    id = try self.ensureFieldSym("ret");
    try self.addFieldSym(sid, id, 2);

    id = try self.ensureTagLitSym("int");
    std.debug.assert(id == TagLit_int);
    id = try self.ensureTagLitSym("i8");
    std.debug.assert(id == TagLit_i8);
    id = try self.ensureTagLitSym("u8");
    std.debug.assert(id == TagLit_u8);
    id = try self.ensureTagLitSym("i16");
    std.debug.assert(id == TagLit_i16);
    id = try self.ensureTagLitSym("u16");
    std.debug.assert(id == TagLit_u16);
    id = try self.ensureTagLitSym("i32");
    std.debug.assert(id == TagLit_i32);
    id = try self.ensureTagLitSym("u32");
    std.debug.assert(id == TagLit_u32);
    id = try self.ensureTagLitSym("f32");
    std.debug.assert(id == TagLit_f32);
    id = try self.ensureTagLitSym("f64");
    std.debug.assert(id == TagLit_f64);
    id = try self.ensureTagLitSym("float");
    std.debug.assert(id == TagLit_float);
    id = try self.ensureTagLitSym("double");
    std.debug.assert(id == TagLit_double);
    id = try self.ensureTagLitSym("charPtrZ");
    std.debug.assert(id == TagLit_charPtrZ);
    id = try self.ensureTagLitSym("ptr");
    std.debug.assert(id == TagLit_ptr);

    id = try self.ensureTagLitSym("AssertError");
    std.debug.assert(id == TagLit_AssertError);
    id = try self.ensureTagLitSym("NotFound");
    std.debug.assert(id == TagLit_NotFound);
    id = try self.ensureTagLitSym("running");
    std.debug.assert(id == TagLit_running);
    id = try self.ensureTagLitSym("paused");
    std.debug.assert(id == TagLit_paused);
    id = try self.ensureTagLitSym("done");
    std.debug.assert(id == TagLit_done);

    id = try self.ensureTagLitSym("error");
    std.debug.assert(id == TagLit_error);
    id = try self.ensureTagLitSym("number");
    std.debug.assert(id == TagLit_number);
    id = try self.ensureTagLitSym("object");
    std.debug.assert(id == TagLit_object);
    id = try self.ensureTagLitSym("bool");
    std.debug.assert(id == TagLit_bool);
}

pub fn testEqNear(vm: *cy.UserVM, args: [*]const Value, nargs: u8) Value {
    _ = vm;
    _ = nargs;
    const act = args[0];
    const exp = args[1];

    const actType = act.getUserTag();
    const expType = exp.getUserTag();
    if (actType == expType) {
        if (actType == .number) {
            if (std.math.approxEqAbs(f64, act.asF64(), exp.asF64(), 1e-5)) {
                return Value.True;
            } else {
                println("actual: {} != {}", .{act.asF64(), exp.asF64()});
                return Value.initErrorTagLit(TagLit_AssertError);
            }
        } else {
            println("Expected number, actual: {}", .{actType});
            return Value.initErrorTagLit(TagLit_AssertError);
        }
    } else {
        println("Types do not match:", .{});
        println("actual: {} != {}", .{actType, expType});
        return Value.initErrorTagLit(TagLit_AssertError);
    }
}

pub fn testEq(vm: *cy.UserVM, args: [*]const Value, nargs: u8) Value {
    _ = nargs;
    const act = args[0];
    const exp = args[1];
    defer {
        vm.release(act);
        vm.release(exp);
    }

    const actType = act.getUserTag();
    const expType = exp.getUserTag();
    if (actType == expType) {
        switch (actType) {
            .number => {
                if (act.asF64() == exp.asF64()) {
                    return Value.True;
                } else {
                    println("actual: {} != {}", .{act.asF64(), exp.asF64()});
                    return Value.initErrorTagLit(TagLit_AssertError);
                }
            },
            .string => {
                if (std.mem.eql(u8, gvm.valueAsString(act), gvm.valueAsString(exp))) {
                    return Value.True;
                } else {
                    println("actual: '{s}' != '{s}'", .{gvm.valueAsString(act), gvm.valueAsString(exp)});
                    return Value.initErrorTagLit(TagLit_AssertError);
                }
            },
            .opaquePtr => {
                const actPtr = stdx.ptrAlignCast(*cy.OpaquePtr, act.asPointer().?).ptr;
                const expPtr = stdx.ptrAlignCast(*cy.OpaquePtr, exp.asPointer().?).ptr;
                if (actPtr == expPtr) {
                    return Value.True;
                } else {
                    println("actual: {*} != {*}", .{actPtr, expPtr});
                    return Value.initErrorTagLit(TagLit_AssertError);
                }
            },
            .boolean => {
                const actv = act.asBool();
                const expv = exp.asBool();
                if (actv == expv) {
                    return Value.True;
                } else {
                    println("actual: {} != {}", .{actv, expv});
                    return Value.initErrorTagLit(TagLit_AssertError);
                }
            },
            .tagLiteral => {
                const actv = act.asTagLiteralId();
                const expv = exp.asTagLiteralId();
                if (actv == expv) {
                    return Value.True;
                } else {
                    println("actual: {s} != {s}", .{gvm.tagLitSyms.buf[actv].name, gvm.tagLitSyms.buf[expv].name});
                    return Value.initErrorTagLit(TagLit_AssertError);
                }
            },
            .none => {
                return Value.True;
            },
            .errorVal => {
                const actv = act.asErrorTagLit();
                const expv = exp.asErrorTagLit();
                if (actv == expv) {
                    return Value.True;
                } else {
                    println("actual: error({s}) != error({s})", .{gvm.tagLitSyms.buf[actv].name, gvm.tagLitSyms.buf[expv].name});
                    return Value.initErrorTagLit(TagLit_AssertError);
                }
            },
            else => {
                stdx.panicFmt("Unsupported type {}", .{actType});
            }
        }
    } else {
        println("Types do not match:", .{});
        println("actual: {} != {}", .{actType, expType});
        return Value.initErrorTagLit(TagLit_AssertError);
    }
}

const testStdOutLog = stdx.log.scoped(.stdout);

fn println(comptime format: []const u8, args: anytype) void {
    if (builtin.is_test) {
        testStdOutLog.debug(format, args);
    } else {
        const stdout = std.io.getStdOut().writer();
        stdout.print(format ++ "\n", args) catch stdx.fatal();
    }
}

export fn printInt(n: i32) void {
    std.debug.print("print int: {}\n", .{n});
}

export fn printU64(n: u64) void {
    std.debug.print("print u64: {}\n", .{n});
}

export fn printF64(n: f64) void {
    std.debug.print("print f64: {}\n", .{n});
}

export fn printF32(n: f32) void {
    std.debug.print("print f32: {}\n", .{n});
}

export fn freeCStr(ptr: [*:0]const u8, len: u32) void {
    gvm.alloc.free(ptr[0..len+1]);
}

export fn fromCStr(ptr: [*:0]const u8) Value {
    const slice = std.mem.span(ptr);
    return gvm.allocString(slice) catch stdx.fatal();
}

export fn cGetPtr(val: Value) ?*anyopaque {
    return stdx.ptrAlignCast(*cy.OpaquePtr, val.asPointer().?).ptr;
}

export fn cAllocOpaquePtr(ptr: ?*anyopaque) Value {
    return gvm.allocOpaquePtr(ptr) catch stdx.fatal();
}

export fn cRelease(val: Value) void {
    vm_.release(gvm, val);
}

export fn toCStr(val: Value, len: *u32) [*:0]const u8 {
    if (val.isPointer()) {
        const obj = stdx.ptrAlignCast(*cy.HeapObject, val.asPointer().?);
        const dupe = std.cstr.addNullByte(gvm.alloc, obj.string.ptr[0..obj.string.len]) catch stdx.fatal();
        len.* = @intCast(u32, obj.string.len);
        return dupe.ptr;
    } else {
        const slice = val.asConstStr();
        const dupe = std.cstr.addNullByte(gvm.alloc, gvm.strBuf[slice.start..slice.end]) catch stdx.fatal();
        len.* = slice.len();
        return dupe.ptr;
    }
}

pub fn coreExecCmd(vm: *cy.UserVM, args: [*]const Value, _: u8) Value {
    const alloc = vm.allocator();

    const list = args[0].asHeapObject(*cy.CyList);
    var buf: std.ArrayListUnmanaged([]const u8) = .{};
    defer buf.deinit(alloc);
    for (list.items()) |arg| {
        buf.append(alloc, vm.valueToString(arg) catch stdx.fatal()) catch stdx.fatal();
    }

    const res = std.ChildProcess.exec(.{
        .allocator = alloc,
        .argv = buf.items,
    }) catch |err| {
        std.debug.print("exec err {}\n", .{err});
        stdx.fatal();
    };

    const map = gvm.allocEmptyMap() catch stdx.fatal();
    const outKey = gvm.allocString("out") catch stdx.fatal();
    const out = vm.allocOwnedString(res.stdout) catch stdx.fatal();
    gvm.setIndex(map, outKey, out) catch stdx.fatal();
    const errKey = gvm.allocString("err") catch stdx.fatal();
    const err = vm.allocOwnedString(res.stderr) catch stdx.fatal();
    gvm.setIndex(map, errKey, err) catch stdx.fatal();
    return map;
}

pub fn coreFetchUrl(vm: *cy.UserVM, args: [*]const Value, _: u8) Value {
    const alloc = vm.allocator();
    const url = vm.valueToTempString(args[0]);
    const res = std.ChildProcess.exec(.{
        .allocator = alloc,
        .argv = &.{ "curl", url },
    }) catch stdx.fatal();
    alloc.free(res.stderr);
    return vm.allocOwnedString(res.stdout) catch stdx.fatal();
}

pub fn coreBindLib(vm: *cy.UserVM, args: [*]const Value, nargs: u8) linksection(StdSection) Value {
    _ = nargs;
    const path = args[0];
    const alloc = vm.allocator();

    defer {
        vm.release(args[0]);
        vm.release(args[1]);
    }

    var lib = alloc.create(std.DynLib) catch stdx.fatal();
    if (path.isNone()) {
        lib.* = std.DynLib.openZ("") catch stdx.fatal();
    } else {
        lib.* = std.DynLib.open(gvm.valueToTempString(path)) catch |err| {
            log.debug("{}", .{err});
            alloc.destroy(lib);
            return Value.initErrorTagLit(TagLit_NotFound);
        };
    }

    // Check that symbols exist.
    const cfuncs = stdx.ptrAlignCast(*cy.CyList, args[1].asPointer().?);
    var cfuncPtrs = alloc.alloc(*anyopaque, cfuncs.items().len) catch stdx.fatal();
    defer alloc.free(cfuncPtrs);
    const symf = gvm.ensureFieldSym("sym") catch stdx.fatal();
    for (cfuncs.items()) |cfunc, i| {
        const sym = gvm.valueToTempString(gvm.getField(cfunc, symf) catch stdx.fatal());
        const symz = std.cstr.addNullByte(alloc, sym) catch stdx.fatal();
        defer alloc.free(symz);
        if (lib.lookup(*anyopaque, symz)) |ptr| {
            cfuncPtrs[i] = ptr;
        } else stdx.panicFmt("Missing sym: {s}", .{sym});
    }

    // Generate c code.
    var csrc: std.ArrayListUnmanaged(u8) = .{};
    defer csrc.deinit(alloc);
    const w = csrc.writer(alloc);

    w.print(
        \\#define uint64_t unsigned long long
        \\#define int8_t signed char
        \\#define uint8_t unsigned char
        \\#define int16_t short
        \\#define uint16_t unsigned short
        \\#define uint32_t unsigned int
        // \\float printF32(float);
        \\extern char* icyToCStr(uint64_t, uint32_t*);
        \\extern void icyFreeCStr(char*, uint32_t);
        \\extern uint64_t icyFromCStr(char*);
        \\extern void icyRelease(uint64_t);
        \\extern void* icyGetPtr(uint64_t);
        \\extern uint64_t icyAllocOpaquePtr(void*);
        \\
    , .{}) catch stdx.fatal();

    const argsf = gvm.ensureFieldSym("args") catch stdx.fatal();
    const retf = gvm.ensureFieldSym("ret") catch stdx.fatal();
    for (cfuncs.items()) |cfunc| {
        const sym = gvm.valueToTempString(gvm.getField(cfunc, symf) catch stdx.fatal());
        const cargsv = gvm.getField(cfunc, argsf) catch stdx.fatal();
        const ret = gvm.getField(cfunc, retf) catch stdx.fatal();

        const cargs = stdx.ptrAlignCast(*cy.CyList, cargsv.asPointer().?);
        const lastArg = cargs.items().len - 1;

        // Emit extern declaration.
        w.print("extern ", .{}) catch stdx.fatal();
        const retTag = ret.asTagLiteralId();
        switch (retTag) {
            TagLit_i32,
            TagLit_int => {
                w.print("int", .{}) catch stdx.fatal();
            },
            TagLit_i8 => {
                w.print("int8_t", .{}) catch stdx.fatal();
            },
            TagLit_u8 => {
                w.print("uint8_t", .{}) catch stdx.fatal();
            },
            TagLit_i16 => {
                w.print("int16_t", .{}) catch stdx.fatal();
            },
            TagLit_u16 => {
                w.print("uint16_t", .{}) catch stdx.fatal();
            },
            TagLit_u32 => {
                w.print("uint32_t", .{}) catch stdx.fatal();
            },
            TagLit_float,
            TagLit_f32 => {
                w.print("float", .{}) catch stdx.fatal();
            },
            TagLit_double,
            TagLit_f64 => {
                w.print("double", .{}) catch stdx.fatal();
            },
            TagLit_charPtrZ => {
                w.print("char*", .{}) catch stdx.fatal();
            },
            TagLit_ptr => {
                w.print("void*", .{}) catch stdx.fatal();
            },
            else => stdx.panicFmt("Unsupported return type: {s}", .{ gvm.getTagLitName(retTag) }),
        }
        w.print(" {s}(", .{sym}) catch stdx.fatal();
        for (cargs.items()) |carg, i| {
            const argTag = carg.asTagLiteralId();
            switch (argTag) {
                TagLit_i32,
                TagLit_int => {
                    w.print("int", .{}) catch stdx.fatal();
                },
                TagLit_i8 => {
                    w.print("int8_t", .{}) catch stdx.fatal();
                },
                TagLit_u8 => {
                    w.print("uint8_t", .{}) catch stdx.fatal();
                },
                TagLit_i16 => {
                    w.print("int16_t", .{}) catch stdx.fatal();
                },
                TagLit_u16 => {
                    w.print("uint16_t", .{}) catch stdx.fatal();
                },
                TagLit_u32 => {
                    w.print("uint32_t", .{}) catch stdx.fatal();
                },
                TagLit_float,
                TagLit_f32 => {
                    w.print("float", .{}) catch stdx.fatal();
                },
                TagLit_double,
                TagLit_f64 => {
                    w.print("double", .{}) catch stdx.fatal();
                },
                TagLit_charPtrZ => {
                    w.print("char*", .{}) catch stdx.fatal();
                },
                TagLit_ptr => {
                    w.print("void*", .{}) catch stdx.fatal();
                },
                else => stdx.panicFmt("Unsupported arg type: {s}", .{ gvm.getTagLitName(argTag) }),
            }
            if (i != lastArg) {
                w.print(", ", .{}) catch stdx.fatal();
            }
        }
        w.print(");\n", .{}) catch stdx.fatal();

        w.print("uint64_t cy{s}(void* vm, uint64_t* args, char numArgs) {{\n", .{sym}) catch stdx.fatal();
        // w.print("  printF64(*(double*)&args[0]);\n", .{}) catch stdx.fatal();
        for (cargs.items()) |carg, i| {
            const argTag = carg.asTagLiteralId();
            switch (argTag) {
                TagLit_charPtrZ => {
                    w.print("  uint32_t strLen{};\n", .{i}) catch stdx.fatal();
                    w.print("  char* str{} = icyToCStr(args[{}], &strLen{});\n", .{i, i, i}) catch stdx.fatal();
                },
                else => {},
            }
        }

        switch (retTag) {
            TagLit_i8,
            TagLit_u8,
            TagLit_i16,
            TagLit_u16,
            TagLit_i32,
            TagLit_u32,
            TagLit_f32,
            TagLit_float,
            TagLit_int => {
                w.print("  double res = (double){s}(", .{sym}) catch stdx.fatal();
            },
            TagLit_f64,
            TagLit_double => {
                w.print("  double res = {s}(", .{sym}) catch stdx.fatal();
            },
            TagLit_charPtrZ => {
                w.print("  char* res = {s}(", .{sym}) catch stdx.fatal();
            },
            TagLit_ptr => {
                w.print("  void* res = {s}(", .{sym}) catch stdx.fatal();
            },
            else => stdx.panicFmt("Unsupported return type: {s}", .{ gvm.getTagLitName(retTag) }),
        }

        // Gen args.
        for (cargs.items()) |carg, i| {
            const argTag = carg.asTagLiteralId();
            switch (argTag) {
                TagLit_i32,
                TagLit_int => {
                    w.print("(int)*(double*)&args[{}]", .{i}) catch stdx.fatal();
                },
                TagLit_i8 => {
                    w.print("(int8_t)*(double*)&args[{}]", .{i}) catch stdx.fatal();
                },
                TagLit_u8 => {
                    w.print("(uint8_t)*(double*)&args[{}]", .{i}) catch stdx.fatal();
                },
                TagLit_i16 => {
                    w.print("(int16_t)*(double*)&args[{}]", .{i}) catch stdx.fatal();
                },
                TagLit_u16 => {
                    w.print("(uint16_t)*(double*)&args[{}]", .{i}) catch stdx.fatal();
                },
                TagLit_u32 => {
                    w.print("(uint32_t)*(double*)&args[{}]", .{i}) catch stdx.fatal();
                },
                TagLit_float,
                TagLit_f32 => {
                    w.print("(float)*(double*)&args[{}]", .{i}) catch stdx.fatal();
                },
                TagLit_double,
                TagLit_f64 => {
                    w.print("*(double*)&args[{}]", .{i}) catch stdx.fatal();
                },
                TagLit_charPtrZ => {
                    w.print("str{}", .{i}) catch stdx.fatal();
                },
                TagLit_ptr => {
                    w.print("icyGetPtr(args[{}])", .{i}) catch stdx.fatal();
                },
                else => stdx.panicFmt("Unsupported arg type: {s}", .{ gvm.getTagLitName(argTag) }),
            }
            if (i != lastArg) {
                w.print(", ", .{}) catch stdx.fatal();
            }
        }

        // End of args.
        w.print(");\n", .{}) catch stdx.fatal();

        for (cargs.items()) |carg, i| {
            const argTag = carg.asTagLiteralId();
            switch (argTag) {
                TagLit_charPtrZ => {
                    w.print("  icyFreeCStr(str{}, strLen{});\n", .{i, i}) catch stdx.fatal();
                    w.print("  icyRelease(args[{}]);\n", .{i}) catch stdx.fatal();
                },
                TagLit_ptr => {
                    w.print("  icyRelease(args[{}]);\n", .{i}) catch stdx.fatal();
                },
                else => {},
            }
        }

        // Gen return.
        switch (retTag) {
            TagLit_i8,
            TagLit_u8,
            TagLit_i16,
            TagLit_u16,
            TagLit_i32,
            TagLit_u32,
            TagLit_f32,
            TagLit_float,
            TagLit_f64,
            TagLit_double,
            TagLit_int => {
                w.print("  return *(uint64_t*)&res;\n", .{}) catch stdx.fatal();
            },
            TagLit_charPtrZ => {
                w.print("  return icyFromCStr(res);\n", .{}) catch stdx.fatal();
            },
            TagLit_ptr => {
                w.print("  return icyAllocOpaquePtr(res);\n", .{}) catch stdx.fatal();
            },
            else => stdx.fatal(),
        }
        w.print("}}\n", .{}) catch stdx.fatal();
    }

    w.writeByte(0) catch stdx.fatal();
    // log.debug("{s}", .{csrc.items});

    const state = tcc.tcc_new();
    // Don't include libtcc1.a.
    tcc.tcc_set_options(state, "-nostdlib");
    _ = tcc.tcc_set_output_type(state, tcc.TCC_OUTPUT_MEMORY);

    if (tcc.tcc_compile_string(state, csrc.items.ptr) == -1) {
        stdx.panic("Failed to compile c source.");
    }

    // const __floatundisf = @extern(*anyopaque, .{ .name = "__floatundisf", .linkage = .Strong });
    // _ = tcc.tcc_add_symbol(state, "__floatundisf", __floatundisf);
    // _ = tcc.tcc_add_symbol(state, "printU64", printU64);
    // _ = tcc.tcc_add_symbol(state, "printF64", printF64);
    // _ = tcc.tcc_add_symbol(state, "printF32", printF32);
    // _ = tcc.tcc_add_symbol(state, "printInt", printInt);
    _ = tcc.tcc_add_symbol(state, "icyFromCStr", fromCStr);
    _ = tcc.tcc_add_symbol(state, "icyToCStr", toCStr);
    _ = tcc.tcc_add_symbol(state, "icyFreeCStr", freeCStr);
    _ = tcc.tcc_add_symbol(state, "icyRelease", cRelease);
    _ = tcc.tcc_add_symbol(state, "icyGetPtr", cGetPtr);
    _ = tcc.tcc_add_symbol(state, "icyAllocOpaquePtr", cAllocOpaquePtr);

    // Add binded symbols.
    for (cfuncs.items()) |cfunc, i| {
        const sym = gvm.valueToTempString(gvm.getField(cfunc, symf) catch stdx.fatal());
        const symz = std.cstr.addNullByte(alloc, sym) catch stdx.fatal();
        defer alloc.free(symz);
        _ = tcc.tcc_add_symbol(state, symz.ptr, cfuncPtrs[i]);
    }

    if (tcc.tcc_relocate(state, tcc.TCC_RELOCATE_AUTO) < 0) {
        stdx.panic("Failed to relocate compiled code.");
    }

    // Create vm function pointers and put in map.
    const map = gvm.allocEmptyMap() catch stdx.fatal();
    const cyState = gvm.allocTccState(state.?, lib) catch stdx.fatal();
    gvm.retainInc(cyState, @intCast(u32, cfuncs.items().len - 1));
    for (cfuncs.items()) |cfunc| {
        const sym = gvm.valueToTempString(gvm.getField(cfunc, symf) catch stdx.fatal());
        const cySym = std.fmt.allocPrint(alloc, "cy{s}{u}", .{sym, 0}) catch stdx.fatal();
        defer alloc.free(cySym);
        const funcPtr = tcc.tcc_get_symbol(state, cySym.ptr) orelse {
            stdx.panic("Failed to get symbol.");
        };

        const func = @ptrCast(*const fn (*cy.UserVM, [*]Value, u8) Value, funcPtr);
        const key = gvm.allocString(sym) catch stdx.fatal();
        const val = gvm.allocNativeFunc1(func, cyState) catch stdx.fatal();
        gvm.setIndex(map, key, val) catch stdx.fatal();
    }
    return map;
}

pub fn coreOpaque(vm: *cy.UserVM, args: [*]const Value, nargs: u8) Value {
    _ = vm;
    _ = nargs;
    const val = args[0];
    if (val.isNumber()) {
        return gvm.allocOpaquePtr(@intToPtr(?*anyopaque, @floatToInt(u64, val.asF64()))) catch stdx.fatal();
    } else {
        stdx.panicFmt("Unsupported conversion", .{});
    }
}

pub fn coreValtag(_: *cy.UserVM, args: [*]const Value, _: u8) Value {
    const val = args[0];
    switch (val.getUserTag()) {
        .number => return Value.initTagLiteral(TagLit_number),
        .object => return Value.initTagLiteral(TagLit_object),
        .errorVal => return Value.initTagLiteral(TagLit_error),
        .boolean => return Value.initTagLiteral(TagLit_bool),
        else => fmt.panic("Unsupported {}", &.{fmt.v(val.getUserTag())}),
    }
}

pub fn coreError(_: *cy.UserVM, args: [*]const Value, _: u8) linksection(StdSection) Value {
    const val = args[0];
    if (val.isPointer()) {
        stdx.fatal();
    } else {
        if (val.assumeNotPtrIsTagLiteral()) {
            return Value.initErrorTagLit(@intCast(u8, val.asTagLiteralId()));
        } else {
            stdx.fatal();
        }
    }
}

pub fn coreBool(vm: *cy.UserVM, args: [*]const Value, _: u8) Value {
    defer vm.release(args[0]);
    return Value.initBool(args[0].toBool());
}

pub fn coreInt(_: *cy.UserVM, args: [*]const Value, _: u8) Value {
    const val = args[0];
    if (val.isNumber()) {
        return Value.initI32(@floatToInt(i32, val.asF64()));
    } else {
        return Value.initI32(0);
    }
}

pub fn coreNumber(vm: *cy.UserVM, args: [*]const Value, nargs: u8) Value {
    _ = vm;
    _ = nargs;
    const val = args[0];
    if (val.isNumber()) {
        return val;
    } else {
        if (val.isPointer()) {
            return Value.initF64(1);
        } else {
            switch (val.getTag()) {
                cy.UserTagT => return Value.initF64(@intToFloat(f64, val.val & @as(u64, 0xFF))),
                cy.UserTagLiteralT => return Value.initF64(@intToFloat(f64, val.val & @as(u64, 0xFF))),
                else => return Value.initF64(1),
            }
        }
    }
}

pub fn coreString(vm: *cy.UserVM, args: [*]const Value, nargs: u8) Value {
    _ = nargs;
    const val = args[0];
    defer vm.release(args[0]);
    if (val.isString()) {
        return val;
    } else {
        const str = gvm.valueToTempString(val);
        return vm.allocString(str) catch stdx.fatal();
    }
}

pub fn corePrint(vm: *cy.UserVM, args: [*]const Value, nargs: u8) Value {
    _ = nargs;
    const str = gvm.valueToTempString(args[0]);
    const w = std.io.getStdOut().writer();
    w.writeAll(str) catch stdx.fatal();
    w.writeByte('\n') catch stdx.fatal();
    vm.release(args[0]);
    return Value.None;
}

pub fn corePrints(vm: *cy.UserVM, args: [*]const Value, nargs: u8) Value {
    _ = nargs;
    const str = gvm.valueToTempString(args[0]);
    const w = std.io.getStdOut().writer();
    w.writeAll(str) catch stdx.fatal();
    vm.release(args[0]);
    return Value.None;
}

pub fn coreWriteFile(vm: *cy.UserVM, args: [*]const Value, _: u8) Value {
    const path = vm.valueToString(args[0]) catch stdx.fatal();
    defer vm.allocator().free(path);
    const content = vm.valueToTempString(args[1]);
    std.fs.cwd().writeFile(path, content) catch stdx.fatal();
    return Value.None;
}

pub fn coreReadFile(vm: *cy.UserVM, args: [*]const Value, _: u8) Value {
    const path = vm.valueToTempString(args[0]);
    const content = std.fs.cwd().readFileAlloc(vm.allocator(), path, 10e8) catch stdx.fatal();
    return vm.allocOwnedString(content) catch stdx.fatal();
}

pub fn coreReadAll(_: *cy.UserVM, _: [*]const Value, _: u8) Value {
    const input = std.io.getStdIn().readToEndAlloc(gvm.alloc, 10e8) catch stdx.fatal();
    return gvm.allocOwnedString(input) catch stdx.fatal();
}

pub fn coreReadLine(_: *cy.UserVM, _: [*]const Value, _: u8) Value {
    const input = std.io.getStdIn().reader().readUntilDelimiterAlloc(gvm.alloc, '\n', 10e8) catch stdx.fatal();
    return gvm.allocOwnedString(input) catch stdx.fatal();
}

pub fn coreParseCyon(vm: *cy.UserVM, args: [*]const Value, nargs: u8) linksection(StdSection) Value {
    _ = nargs;
    const str = gvm.valueAsString(args[0]);
    defer vm.release(args[0]);

    var parser = cy.Parser.init(gvm.alloc);
    defer parser.deinit();
    const val = cy.decodeCyon(gvm.alloc, &parser, str) catch stdx.fatal();
    return fromCyonValue(vm, val) catch stdx.fatal();
}

fn fromCyonValue(self: *cy.UserVM, val: cy.DecodeValueIR) !Value {
    switch (val.getValueType()) {
        .list => {
            var dlist = val.asList() catch stdx.fatal();
            defer dlist.deinit();
            const elems = try gvm.alloc.alloc(Value, dlist.arr.len);
            for (elems) |*elem, i| {
                elem.* = try fromCyonValue(self, dlist.getIndex(i));
            }
            return try gvm.allocOwnedList(elems);
        },
        .map => {
            var dmap = val.asMap() catch stdx.fatal();
            defer dmap.deinit();
            var iter = dmap.iterator();

            const mapVal = try gvm.allocEmptyMap();
            const map = stdx.ptrAlignCast(*cy.HeapObject, mapVal.asPointer().?);
            while (iter.next()) |entry| {
                const child = try fromCyonValue(self, dmap.getValue(entry.key_ptr.*));
                const key = try self.allocString(entry.key_ptr.*);
                stdMapPut(self, map, key, child);
            }
            return mapVal;
        },
        .string => {
            const str = try val.allocString();
            return try gvm.allocOwnedString(str);
        },
        .number => {
            return Value.initF64(try val.asF64());
        },
    }
}

fn stdMapPut(_: *cy.UserVM, obj: *cy.HeapObject, key: Value, value: Value) void {
    const map = stdx.ptrAlignCast(*cy.MapInner, &obj.map.inner); 
    map.put(gvm.alloc, gvm, key, value) catch stdx.fatal();
}

fn listSort(vm: *cy.UserVM, ptr: *anyopaque, args: [*]const Value, nargs: u8) Value {
    if (nargs == 0) {
        stdx.panic("Args mismatch");
    }

    const obj = stdx.ptrAlignCast(*cy.HeapObject, ptr);
    const list = stdx.ptrAlignCast(*cy.List(Value), &obj.list.list);
    const LessContext = struct {
        lessFn: Value,
        vm: *cy.UserVM,
        newFramePtr: u32,
    };
    var lessCtx = LessContext{
        .lessFn = args[0],
        .vm = vm,
        .newFramePtr = vm.getNewFramePtrOffset(args),
    };

    const S = struct {
        fn less(ctx_: *LessContext, a: Value, b: Value) bool {
            const res = ctx_.vm.callFunc(ctx_.newFramePtr, ctx_.lessFn, &.{a, b}) catch stdx.fatal();
            return res.toBool();
        }
    };
    std.sort.sort(Value, list.items(), &lessCtx, S.less);
    vm.releaseObject(obj);
    return Value.None;
}

fn listRemove(_: *cy.UserVM, ptr: *anyopaque, args: [*]const Value, nargs: u8) Value {
    _ = nargs;
    const index = @floatToInt(usize, args[0].toF64());
    const list = stdx.ptrAlignCast(*cy.HeapObject, ptr);
    const inner = stdx.ptrAlignCast(*cy.List(Value), &list.list.list);
    inner.remove(index);
    vm_.releaseObject(gvm, list);
    return Value.None;
}

fn listInsert(_: *cy.UserVM, ptr: *anyopaque, args: [*]const Value, nargs: u8) Value {
    _ = nargs;
    const index = @floatToInt(usize, args[0].toF64());
    const value = args[1];
    const list = stdx.ptrAlignCast(*cy.HeapObject, ptr);
    const inner = stdx.ptrAlignCast(*cy.List(Value), &list.list.list);
    if (inner.len == inner.buf.len) {
        inner.growTotalCapacity(gvm.alloc, inner.len + 1) catch stdx.fatal();
    }
    inner.insertAssumeCapacity(index, value);
    vm_.releaseObject(gvm, list);
    return Value.None;
}

fn listAdd(vm: *cy.UserVM, ptr: *anyopaque, args: [*]const Value, nargs: u8) Value {
    if (nargs == 0) {
        stdx.panic("Args mismatch");
    }
    const list = stdx.ptrAlignCast(*cy.HeapObject, ptr);
    const inner = stdx.ptrAlignCast(*cy.List(Value), &list.list.list);
    if (inner.len == inner.buf.len) {
        // After reaching a certain size, use power of two ceil.
        // This reduces allocations for big lists while not over allocating for smaller lists.
        if (inner.len > 512) {
            const newCap = std.math.ceilPowerOfTwo(u32, @intCast(u32, inner.len) + 1) catch stdx.fatal();
            inner.growTotalCapacityPrecise(gvm.alloc, newCap) catch stdx.fatal();
        } else {
            inner.growTotalCapacity(gvm.alloc, inner.len + 1) catch stdx.fatal();
        }
    }
    inner.appendAssumeCapacity(args[0]);
    vm.releaseObject(list);
    return Value.None;
}

fn listNextPair(_: *cy.UserVM, ptr: *anyopaque, args: [*]const Value, nargs: u8) cy.ValuePair {
    _ = args;
    _ = nargs;
    const list = stdx.ptrAlignCast(*cy.HeapObject, ptr);
    if (list.list.nextIterIdx < list.list.list.len) {
        defer list.list.nextIterIdx += 1;
        const val = list.list.list.ptr[list.list.nextIterIdx];
        gvm.retain(val);
        return .{
            .left = Value.initF64(@intToFloat(f64, list.list.nextIterIdx)),
            .right = val,
        };
    } else return .{
        .left = Value.None,
        .right = Value.None,
    };
}

fn listNext(_: *cy.UserVM, ptr: *anyopaque, args: [*]const Value, nargs: u8) Value {
    _ = args;
    _ = nargs;
    const list = stdx.ptrAlignCast(*cy.HeapObject, ptr);
    if (list.list.nextIterIdx < list.list.list.len) {
        defer list.list.nextIterIdx += 1;
        const val = list.list.list.ptr[list.list.nextIterIdx];
        gvm.retain(val);
        return val;
    } else return Value.None;
}

fn listIterator(_: *cy.UserVM, ptr: *anyopaque, args: [*]const Value, nargs: u8) Value {
    _ = args;
    _ = nargs;
    const list = stdx.ptrAlignCast(*cy.HeapObject, ptr);
    gvm.retainObject(list);
    list.list.nextIterIdx = 0;
    return Value.initPtr(ptr);
}

fn listResize(_: *cy.UserVM, ptr: *anyopaque, args: [*]const Value, nargs: u8) Value {
    if (nargs == 0) {
        stdx.panic("Args mismatch");
    }
    const list = stdx.ptrAlignCast(*cy.HeapObject, ptr);
    const inner = stdx.ptrAlignCast(*cy.List(Value), &list.list.list);
    const size = @floatToInt(u32, args[0].toF64());
    inner.resize(gvm.alloc, size) catch stdx.fatal();
    vm_.releaseObject(gvm, list);
    return Value.None;
}

fn mapIterator(vm: *cy.UserVM, ptr: *anyopaque, args: [*]const Value, nargs: u8) linksection(Section) Value {
    _ = nargs;
    _ = args;
    const obj = stdx.ptrAlignCast(*cy.HeapObject, ptr);
    vm.retainObject(obj);
    obj.map.inner.extra = 0;
    return Value.initPtr(ptr);
}

fn mapNextPair(_: *cy.UserVM, ptr: *anyopaque, args: [*]const Value, nargs: u8) linksection(Section) cy.ValuePair {
    _ = args;
    _ = nargs;
    const obj = stdx.ptrAlignCast(*cy.HeapObject, ptr);
    const map = @ptrCast(*cy.ValueMap, &obj.map.inner);
    if (map.next()) |entry| {
        gvm.retain(entry.key);
        gvm.retain(entry.value);
        return .{
            .left = entry.key,
            .right = entry.value,
        };
    } else return .{
        .left = Value.None,
        .right = Value.None,
    };
}

fn mapNext(_: *cy.UserVM, ptr: *anyopaque, args: [*]const Value, nargs: u8) linksection(Section) Value {
    _ = args;
    _ = nargs;
    const obj = stdx.ptrAlignCast(*cy.HeapObject, ptr);
    const map = @ptrCast(*cy.ValueMap, &obj.map.inner);
    if (map.next()) |entry| {
        gvm.retain(entry.value);
        return entry.value;
    } else return Value.None;
}

fn mapSize(_: *cy.UserVM, ptr: *anyopaque, args: [*]const Value, nargs: u8) Value {
    _ = nargs;
    _ = args;
    const obj = stdx.ptrAlignCast(*cy.HeapObject, ptr);
    const inner = stdx.ptrAlignCast(*cy.MapInner, &obj.map.inner);
    vm_.releaseObject(gvm, obj);
    return Value.initF64(@intToFloat(f64, inner.size));
}

fn mapRemove(_: *cy.UserVM, ptr: *anyopaque, args: [*]const Value, nargs: u8) Value {
    if (nargs == 0) {
        stdx.panic("Args mismatch");
    }
    const obj = stdx.ptrAlignCast(*cy.HeapObject, ptr);
    const inner = stdx.ptrAlignCast(*cy.MapInner, &obj.map.inner);
    _ = inner.remove(gvm, args[0]);
    return Value.None;
}

fn listSize(_: *cy.UserVM, ptr: *anyopaque, args: [*]const Value, nargs: u8) Value {
    @setRuntimeSafety(debug);
    _ = nargs;
    _ = args;
    const list = stdx.ptrAlignCast(*cy.HeapObject, ptr);
    const inner = stdx.ptrAlignCast(*cy.List(Value), &list.list.list);
    vm_.releaseObject(gvm, list);
    return Value.initF64(@intToFloat(f64, inner.len));
}

pub fn mathAbs(_: *cy.UserVM, args: [*]const Value, _: u8) Value {
    return Value.initF64(@fabs(args[0].toF64()));
}

pub fn mathCeil(_: *cy.UserVM, args: [*]const Value, _: u8) Value {
    return Value.initF64(std.math.ceil(args[0].toF64()));
}

pub fn mathFloor(_: *cy.UserVM, args: [*]const Value, _: u8) Value {
    return Value.initF64(std.math.floor(args[0].toF64()));
}

pub fn mathRound(_: *cy.UserVM, args: [*]const Value, _: u8) Value {
    return Value.initF64(std.math.round(args[0].toF64()));
}

pub fn mathTrunc(_: *cy.UserVM, args: [*]const Value, _: u8) Value {
    return Value.initF64(std.math.trunc(args[0].toF64()));
}

pub fn mathMax(_: *cy.UserVM, args: [*]const Value, _: u8) Value {
    return Value.initF64(std.math.max(args[0].toF64(), args[1].toF64()));
}

pub fn mathMin(_: *cy.UserVM, args: [*]const Value, _: u8) Value {
    return Value.initF64(std.math.min(args[0].toF64(), args[1].toF64()));
}

pub fn mathSign(_: *cy.UserVM, args: [*]const Value, _: u8) Value {
    return Value.initF64(std.math.sign(args[0].toF64()));
}

pub fn mathClz32(_: *cy.UserVM, args: [*]const Value, _: u8) Value {
    return Value.initF64(@intToFloat(f64, @clz(@floatToInt(i32, args[0].toF64()))));
}

pub fn mathMul32(_: *cy.UserVM, args: [*]const Value, _: u8) Value {
    return Value.initF64(@intToFloat(f64, @floatToInt(i32, args[0].toF64()) *% @floatToInt(i32, args[1].toF64())));
}

pub fn mathExp(_: *cy.UserVM, args: [*]const Value, _: u8) Value {
    return Value.initF64(std.math.exp(args[0].toF64()));
}

pub fn mathExpm1(_: *cy.UserVM, args: [*]const Value, _: u8) Value {
    return Value.initF64(std.math.expm1(args[0].toF64()));
}

pub fn mathLog(_: *cy.UserVM, args: [*]const Value, _: u8) Value {
    return Value.initF64(std.math.log(f64, args[0].toF64(), args[1].toF64()));
}

pub fn mathLog1p(_: *cy.UserVM, args: [*]const Value, _: u8) Value {
    return Value.initF64(std.math.log1p(args[0].toF64()));
}

pub fn mathLog10(_: *cy.UserVM, args: [*]const Value, _: u8) Value {
    return Value.initF64(std.math.log10(args[0].toF64()));
}

pub fn mathLog2(_: *cy.UserVM, args: [*]const Value, _: u8) Value {
    return Value.initF64(std.math.log2(args[0].toF64()));
}

pub fn mathLn(_: *cy.UserVM, args: [*]const Value, _: u8) Value {
    return Value.initF64(std.math.ln(args[0].toF64()));
}

pub fn mathIsNaN(_: *cy.UserVM, args: [*]const Value, _: u8) Value {
    return Value.initBool(std.math.isNan(args[0].toF64()));
}

pub fn mathPow(_: *cy.UserVM, args: [*]const Value, _: u8) Value {
    return Value.initF64(std.math.pow(f64, args[0].toF64(), args[1].toF64()));
}

pub fn mathHypot(_: *cy.UserVM, args: [*]const Value, _: u8) Value {
    return Value.initF64(std.math.hypot(f64, args[0].toF64(), args[1].toF64()));
}

pub fn mathSqrt(_: *cy.UserVM, args: [*]const Value, _: u8) Value {
    return Value.initF64(std.math.sqrt(args[0].toF64()));
}

pub fn mathCbrt(_: *cy.UserVM, args: [*]const Value, _: u8) Value {
    return Value.initF64(std.math.cbrt(args[0].toF64()));
}

var rand = std.rand.DefaultPrng.init(0);
pub fn mathRandom(_: *cy.UserVM, _: [*]const Value, _: u8) Value {
    return Value.initF64(rand.random().float(f64));
}

pub fn mathCos(_: *cy.UserVM, args: [*]const Value, _: u8) Value {
    return Value.initF64(std.math.cos(args[0].toF64()));
}

pub fn mathSin(_: *cy.UserVM, args: [*]const Value, _: u8) Value {
    return Value.initF64(std.math.sin(args[0].toF64()));
}

pub fn mathTan(_: *cy.UserVM, args: [*]const Value, _: u8) Value {
    return Value.initF64(std.math.tan(args[0].toF64()));
}

pub fn mathCosh(_: *cy.UserVM, args: [*]const Value, _: u8) Value {
    return Value.initF64(std.math.cosh(args[0].toF64()));
}

pub fn mathSinh(_: *cy.UserVM, args: [*]const Value, _: u8) Value {
    return Value.initF64(std.math.sinh(args[0].toF64()));
}

pub fn mathTanh(_: *cy.UserVM, args: [*]const Value, _: u8) Value {
    return Value.initF64(std.math.tanh(args[0].toF64()));
}

pub fn mathAcos(_: *cy.UserVM, args: [*]const Value, _: u8) Value {
    return Value.initF64(std.math.acos(args[0].toF64()));
}

pub fn mathAsin(_: *cy.UserVM, args: [*]const Value, _: u8) Value {
    return Value.initF64(std.math.asin(args[0].toF64()));
}

pub fn mathAtan(_: *cy.UserVM, args: [*]const Value, _: u8) Value {
    return Value.initF64(std.math.atan(args[0].toF64()));
}

pub fn mathAtan2(_: *cy.UserVM, args: [*]const Value, _: u8) Value {
    return Value.initF64(std.math.atan2(f64, args[0].toF64(), args[1].toF64()));
}

pub fn mathAcosh(_: *cy.UserVM, args: [*]const Value, _: u8) Value {
    return Value.initF64(std.math.acosh(args[0].toF64()));
}

pub fn mathAsinh(_: *cy.UserVM, args: [*]const Value, _: u8) Value {
    return Value.initF64(std.math.asinh(args[0].toF64()));
}

pub fn mathAtanh(_: *cy.UserVM, args: [*]const Value, _: u8) Value {
    return Value.initF64(std.math.atanh(args[0].toF64()));
}

pub fn osCwd(vm: *cy.UserVM, _: [*]const Value, _: u8) Value {
    const cwd = std.process.getCwdAlloc(vm.allocator()) catch stdx.fatal();
    return vm.allocOwnedString(cwd) catch stdx.fatal();
}

pub fn osRealPath(vm: *cy.UserVM, args: [*]const Value, _: u8) Value {
    const path = vm.valueToTempString(args[0]);
    const res = std.fs.cwd().realpathAlloc(vm.allocator(), path) catch stdx.fatal();
    return vm.allocOwnedString(res) catch stdx.fatal();
}

pub fn osGetEnvAll(vm: *cy.UserVM, _: [*]const Value, _: u8) Value {
    var env = std.process.getEnvMap(vm.allocator()) catch stdx.fatal();
    defer env.deinit();

    const map = gvm.allocEmptyMap() catch stdx.fatal();
    var iter = env.iterator();
    while (iter.next()) |entry| {
        const key = gvm.allocString(entry.key_ptr.*) catch stdx.fatal();
        const val = gvm.allocString(entry.value_ptr.*) catch stdx.fatal();
        gvm.setIndex(map, key, val) catch stdx.fatal();
    }
    return map;
}

pub fn osGetEnv(vm: *cy.UserVM, args: [*]const Value, _: u8) Value {
    const key = vm.valueToTempString(args[0]);
    const res = std.os.getenv(key) orelse return Value.None;
    return vm.allocString(res) catch stdx.fatal();
}

pub fn osSetEnv(vm: *cy.UserVM, args: [*]const Value, _: u8) Value {
    const key = vm.valueToString(args[0]) catch stdx.fatal();
    defer vm.allocator().free(key);
    const keyz = std.cstr.addNullByte(vm.allocator(), key) catch stdx.fatal();
    defer vm.allocator().free(keyz);

    const value = vm.valueToTempString(args[1]);
    const valuez = std.cstr.addNullByte(vm.allocator(), value) catch stdx.fatal();
    defer vm.allocator().free(valuez);
    _ = setenv(keyz, valuez, 1);
    return Value.None;
}

pub fn osUnsetEnv(vm: *cy.UserVM, args: [*]const Value, _: u8) Value {
    const key = vm.valueToTempString(args[0]);
    const keyz = std.cstr.addNullByte(vm.allocator(), key) catch stdx.fatal();
    defer vm.allocator().free(keyz);
    _ = unsetenv(keyz);
    return Value.None;
}

pub extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
pub extern "c" fn unsetenv(name: [*:0]const u8) c_int;

// Keep as reference in case resume should be a function call.
// Although it works, it requires native func calls to perform additional copies of pc and framePtr back to the eval loop,
// which is a bad tradeoff for every other function call that doesn't need to.
// One solution is to add another bytecode to call nativeFunc1 with control over execution context.
// fn fiberResume(vm: *cy.UserVM, ptr: *anyopaque, args: [*]const Value, _: u8) linksection(".eval") Value {
//     const obj = stdx.ptrAlignCast(*cy.HeapObject, ptr);
//     if (&obj.fiber != @ptrCast(*cy.VM, vm).curFiber) {
//         // Only resume fiber if it's not done.
//         if (obj.fiber.pc != NullId) {
//             // Obtain the startLocal from looking at previous inst operand.
//             const startLocal = (@ptrCast(*cy.VM, vm).pc - 14 + 1)[0].arg;
//             // Obtain previous framePtr by subtracting from args pointer.
//             const prevFramePtr = @intToPtr([*]Value, @ptrToInt(args - startLocal - 4));

//             const pcOffset = @intCast(u32, @ptrToInt(@ptrCast(*cy.VM, vm).pc) - @ptrToInt(@ptrCast(*cy.VM, vm).ops.ptr));
//             const res = cy.pushFiber(@ptrCast(*cy.VM, vm), pcOffset, prevFramePtr, &obj.fiber, startLocal);
//             @ptrCast(*cy.VM, vm).pc = res.pc;
//             @ptrCast(*cy.VM, vm).framePtr = res.framePtr;
//             return Value.None;
//         }
//     }
//     vm.releaseObject(obj);
//     return Value.None;
// }

fn fiberStatus(vm: *cy.UserVM, ptr: *anyopaque, _: [*]const Value, _: u8) Value {
    const obj = stdx.ptrAlignCast(*cy.HeapObject, ptr);
    defer vm.releaseObject(obj);

    if (gvm.curFiber == @ptrCast(*cy.Fiber, obj)) {
        return Value.initTagLiteral(TagLit_running);
    } else {
        // Check if done.
        if (obj.fiber.pc == NullId) {
            return Value.initTagLiteral(TagLit_done);
        } else {
            return Value.initTagLiteral(TagLit_paused);
        }
    }
}

fn stringLen(vm: *cy.UserVM, ptr: *anyopaque, _: [*]const Value, _: u8) Value {
    const obj = stdx.ptrAlignCast(*cy.HeapObject, ptr);
    defer vm.releaseObject(obj);
    return Value.initF64(@intToFloat(f64, obj.string.len));
}

fn stringCharAt(vm: *cy.UserVM, ptr: *anyopaque, args: [*]const Value, _: u8) Value {
    const obj = stdx.ptrAlignCast(*cy.HeapObject, ptr);
    defer vm.releaseObject(obj);
    return Value.initF64(@intToFloat(f64, obj.string.ptr[@floatToInt(u32, args[0].toF64())]));
}

fn constStringLen(_: *cy.UserVM, ptr: *anyopaque, _: [*]const Value, _: u8) Value {
    const val = Value{ .val = @ptrToInt(ptr) };
    const str = val.asConstStr();
    return Value.initF64(@intToFloat(f64, str.len()));
}

fn constStringCharAt(_: *cy.UserVM, ptr: *anyopaque, args: [*]const Value, _: u8) Value {
    const val = Value{ .val = @ptrToInt(ptr) };
    const str = val.asConstStr();
    const idx = @floatToInt(u32, args[0].toF64());
    return Value.initF64(@intToFloat(f64, gvm.strBuf[str.start + idx]));
}