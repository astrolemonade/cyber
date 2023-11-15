const std = @import("std");
const builtin = @import("builtin");
const stdx = @import("stdx");
const tcc = @import("tcc");
const cy = @import("../cyber.zig");
const rt = cy.rt;
const Value = cy.Value;
const bindings = @import("../builtins/bindings.zig");
const prepareThrowSymbol = bindings.prepareThrowSymbol;
const Symbol = bindings.Symbol;
const os = @import("os.zig");
const sema = cy.sema;
const bt = cy.types.BuiltinTypes;
const types = cy.types;

const log = cy.log.scoped(.ffi);

const DumpCGen = builtin.mode == .Debug and false;

pub const BindLibConfig = struct {
    /// Whether bindLib generates the binding to an anonymous object type as methods
    /// or a map with functions.
    genMap: bool = false,
};

const Context = struct {
    var buf: [64]u8 = undefined;

    ivm: *cy.VM,
    alloc: std.mem.Allocator,

    /// Ordered to handle C decl rules.
    symToCStructFields: std.AutoArrayHashMapUnmanaged(u32, *cy.CyList) = .{},

    arrays: std.StringHashMapUnmanaged(cy.Value),

    tempTypes: std.ArrayListUnmanaged(types.TypeId),

    config: BindLibConfig,
    nField: u32,
    elemField: u32,

    fn deinit(self: *Context) void {
        self.symToCStructFields.deinit(self.alloc);
        var iter = self.arrays.keyIterator();
        while (iter.next()) |key| {
            self.alloc.free(key.*);
        }
        self.arrays.deinit(self.alloc);
        self.tempTypes.deinit(self.alloc);
    }

    fn ensureArray(self: *Context, bindT: Value) !void {
        const n: u32 = @intCast((try self.ivm.getField(bindT, self.nField)).asInteger());
        const elem = try self.ivm.getField(bindT, self.elemField);
        const elemName = try self.getTempBaseTypeName(elem);
        const key = try std.fmt.bufPrint(&Context.buf, "{s}[{}]", .{elemName, n});
        const res = try self.arrays.getOrPut(self.alloc, key);
        if (!res.found_existing) {
            res.key_ptr.* = try self.alloc.dupe(u8, key);
            res.value_ptr.* = bindT;
        }
    }

    /// eg. int a; int a[4];
    fn genNamedCType(self: *Context, w: anytype, val: Value, name: []const u8) !void {
        if (val.isObjectType(os.CArrayT)) {
            const n = (try self.ivm.getField(val, self.nField)).asInteger();
            const elem = try self.ivm.getField(val, self.elemField);
            try self.genCType(w, elem);
            try w.print(" {s}[{}]", .{ name, n });
        } else {
            try self.genCType(w, val);
            try w.print(" {s}", .{name});
        }
    }

    fn genCType(self: *Context, w: anytype, val: Value) !void {
        if (val.isObjectType(bt.MetaType)) {
            const objType = val.asPointer(*cy.heap.MetaType);
            if (self.symToCStructFields.contains(objType.symId)) {
                try w.print("Struct{}", .{objType.symId});
            } else {
                const name = self.ivm.valueToTempString(val);
                log.debug("CStruct not declared for: {s}", .{name});
                return error.InvalidArgument;
            }
        } else if (val.isObjectType(os.CArrayT)) {
            const n = (try self.ivm.getField(val, self.nField)).asInteger();
            const elem = try self.ivm.getField(val, self.elemField);
            try self.genCType(w, elem);
            try w.print("[{}]", .{ n });
        } else {
            if (val.isSymbol()) {
                const tag = val.asSymbolId();
                const str = switch (@as(Symbol, @enumFromInt(tag))) {
                    .bool => "bool",
                    .char => "int8_t",
                    .uchar => "uint8_t",
                    .short => "int16_t",
                    .ushort => "uint16_t",
                    .int => "int",
                    .uint => "uint32_t",
                    .long => "int64_t",
                    .ulong => "uint64_t",
                    .usize => "size_t",
                    .float => "float",
                    .double => "double",
                    .charPtr => "char*",
                    .voidPtr => "void*",
                    .void => "void",
                    else => {
                        std.debug.print("Unsupported arg type: {s}\n", .{ self.ivm.getSymbolName(tag) });
                        return error.InvalidArgument;
                    },
                };
                try w.writeAll(str);
            } else {
                std.debug.print("Unsupported arg type: {s}\n", .{ self.ivm.valueToTempString(val) });
                return error.InvalidArgument;
            }
        }
    }

    /// Returns the name of a base type. No arrays.
    fn getTempBaseTypeName(self: *Context, val: Value) ![]const u8 {
        const S = struct {
            var buf: [16]u8 = undefined;
        };
        if (val.isObjectType(bt.MetaType)) {
            const objType = val.asPointer(*cy.heap.MetaType);
            if (self.symToCStructFields.contains(objType.symId)) {
                return std.fmt.bufPrint(&S.buf, "Struct{}", .{objType.symId});
            } else {
                const name = self.ivm.valueToTempString(val);
                log.debug("CStruct not declared for: {s}", .{name});
                return error.InvalidArgument;
            }
        } else {
            if (val.isSymbol()) {
                const tag = val.asSymbolId();
                return switch (@as(Symbol, @enumFromInt(tag))) {
                    .bool => "Bool",
                    .char => "I8",
                    .uchar => "U8",
                    .short => "I16",
                    .ushort => "U16",
                    .int => "I32",
                    .uint => "U32",
                    .long => "I64",
                    .ulong => "U64",
                    .usize => "Usize",
                    .float => "Float",
                    .double => "Double",
                    .charPtr => "CharPtr",
                    .voidPtr => "VoidPtr",
                    else => {
                        std.debug.print("Unsupported arg type: {s}\n", .{ self.ivm.getSymbolName(tag) });
                        return error.InvalidArgument;
                    },
                };
            } else {
                std.debug.print("Unsupported arg type: {s}\n", .{ self.ivm.valueToTempString(val) });
                return error.InvalidArgument;
            }
        }
    }

    fn genToCyValue(self: *Context, w: anytype, argType: Value, cval: []const u8) !void {
        if (argType.isObjectType(bt.MetaType)) {
            const objType = argType.asPointer(*cy.heap.MetaType);
            try w.print("fromStruct{}(vm, {s})", .{ objType.symId, cval });
        } else if (argType.isObjectType(os.CArrayT)) {
            const n: u32 = @intCast((try self.ivm.getField(argType, self.nField)).asInteger());
            const elem = try self.ivm.getField(argType, self.elemField);
            const elemName = try self.getTempBaseTypeName(elem);
            try w.print("from{s}Array{}(vm, {s})", .{elemName, n, cval});
        } else {
            const tag = argType.asSymbolId();
            switch (@as(Symbol, @enumFromInt(tag))) {
                .char,
                .short,
                .int,
                .long,
                .ulong,
                .usize => {
                    try w.print("(0x7FFE000000000000 | ({s} & 0xFFFFFFFFFFFF))", .{cval});
                },
                .uchar,
                .ushort,
                .uint => {
                    try w.print("(0x7FFE000000000000 | {s})", .{cval});
                },
                .float,
                .double => {
                    // Assumes cval is already converted to double.
                    try w.print("*(uint64_t*)&{s}", .{cval});
                },
                .charPtr => {
                    try w.print("icyAllocCyPointer(vm, {s})", .{cval});
                },
                .voidPtr => {
                    try w.print("icyAllocCyPointer(vm, {s})", .{cval});
                },
                .void => {
                    try w.print("0x7FFC000000000000", .{});
                },
                .bool => {
                    try w.print("({s} == 1) ? 0x7FFC000100000001 : 0x7FFC000100000000", .{cval});
                },
                else => {
                    log.debug("{s}", .{self.ivm.valueToTempString(argType)});
                    cy.panicFmt("Unsupported arg type: {s}", .{ self.ivm.getSymbolName(tag) });
                }
            }
        }
    }

    /// Assumes `uint64_t* args` is available in the scope.
    fn genToCValueFromArg(self: *Context, w: anytype, argType: Value, i: usize) !void {
        if (argType.isObjectType(bt.MetaType)) {
            const objType = argType.asPointer(*cy.heap.MetaType);
            try w.print("toStruct{}(vm, args[{}])", .{objType.symId, i});
        } else {
            if (argType.isSymbol()) {
                const tag = argType.asSymbolId();
                switch (@as(Symbol, @enumFromInt(tag))) {
                    .bool => {
                        try w.print("(args[{}] == 0x7FFC000100000001)?1:0", .{i});
                    },
                    .char => {
                        try w.print("(int8_t)(args[{}] & 0xFFFFFFFFFFFF)", .{i});
                    },
                    .uchar => {
                        try w.print("(uint8_t)(args[{}] & 0xFFFFFFFFFFFF)", .{i});
                    },
                    .short => {
                        try w.print("(int16_t)(args[{}] & 0xFFFFFFFFFFFF)", .{i});
                    },
                    .ushort => {
                        try w.print("(uint16_t)(args[{}] & 0xFFFFFFFFFFFF)", .{i});
                    },
                    .int => {
                        try w.print("(int)(args[{}] & 0xFFFFFFFFFFFF)", .{i});
                    },
                    .uint => {
                        try w.print("(uint32_t)(args[{}] & 0xFFFFFFFFFFFF)", .{i});
                    },
                    .long => {
                        // 48-bit int to 64-bit.
                        try w.print("(((int64_t)(args[{}] & 0xFFFFFFFFFFFF) << 16) >> 16)", .{i});
                    },
                    .ulong => {
                        try w.print("(uint64_t)(args[{}] & 0xFFFFFFFFFFFF)", .{i});
                    },
                    .usize => {
                        try w.print("(size_t)(args[{}] & 0xFFFFFFFFFFFF)", .{i});
                    },
                    .float => {
                        try w.print("(float)*(double*)&args[{}]", .{i});
                    },
                    .double => {
                        try w.print("*(double*)&args[{}]", .{i});
                    },
                    .charPtr => {
                        try w.print("(char*)icyGetPtr(args[{}])", .{i});
                    },
                    .voidPtr => {
                        try w.print("icyGetPtr(args[{}])", .{i});
                    },
                    else => {
                        std.debug.print("Unsupported arg type: {s}\n", .{ self.ivm.getSymbolName(tag) });
                        return error.InvalidArgument;
                    }
                }
            } else {
                std.debug.print("Unsupported arg type: {s}\n", .{ self.ivm.valueToTempString(argType) });
                return error.InvalidArgument;
            }
        }
    }
};

fn toSemaType(ivm: *cy.VM, val: Value) !types.TypeId {
    if (val.isSymbol()) {
        const tag = val.asSymbolId();
        switch (@as(Symbol, @enumFromInt(tag))) {
            .bool => return bt.Boolean,
            .char => return bt.Integer,
            .uchar => return bt.Integer,
            .short => return bt.Integer,
            .ushort => return bt.Integer,
            .int => return bt.Integer,
            .uint => return bt.Integer,
            .long => return bt.Integer,
            .ulong => return bt.Integer,
            .usize => return bt.Integer,
            .float => return bt.Float,
            .double => return bt.Float,
            .charPtr => return bt.Pointer,
            .voidPtr => return bt.Pointer,
            .void => return bt.None,
            else => {
                std.debug.print("Unsupported val type: {s}\n", .{ ivm.getSymbolName(tag) });
                return error.InvalidArgument;
            }
        }
    } else {
        std.debug.print("Unsupported val type: {s}\n", .{ ivm.valueToTempString(val) });
        return error.InvalidArgument;
    }
}

pub fn bindLib(vm: *cy.UserVM, args: [*]const Value, config: BindLibConfig) !Value {
    const path = args[0];
    const alloc = vm.allocator();
    const ivm: *cy.VM = @ptrCast(vm);

    var success = false;

    var lib = try alloc.create(std.DynLib);
    defer {
        if (!success) {
            alloc.destroy(lib);
        }
    }

    if (path.isNone()) {
        if (builtin.os.tag == .macos) {
            const exe = try std.fs.selfExePathAlloc(alloc);
            defer alloc.free(exe);
            lib.* = try dlopen(exe);
        } else {
            lib.* = try dlopen("");
        }
    } else {
        log.tracev("bindLib {s}", .{vm.valueToTempString(path)});
        lib.* = dlopen(vm.valueToTempString(path)) catch |err| {
            if (err == error.FileNotFound) {
                return prepareThrowSymbol(vm, .FileNotFound);
            } else {
                return err;
            }
        };
    }

    var ctx = Context{
        .ivm = ivm,
        .alloc = alloc,
        .symToCStructFields = .{},
        .arrays = .{},
        .tempTypes = .{},
        .config = config,
        .nField = try ivm.ensureFieldSym("n"),
        .elemField = try ivm.ensureFieldSym("elem"),
    };
    defer ctx.deinit();

    var cfuncs: std.ArrayListUnmanaged(CFuncData) = .{};
    defer cfuncs.deinit(alloc);

    const decls = args[1].asPointer(*cy.CyList);

    const argsf = try ivm.ensureFieldSym("args");
    const retf = try ivm.ensureFieldSym("ret");

    // Check that symbols exist and build the model.
    const symF = try ivm.ensureFieldSym("sym");
    const fieldsF = try ivm.ensureFieldSym("fields");
    const typeF = try ivm.ensureFieldSym("type");
    for (decls.items()) |decl| {
        if (decl.isObjectType(os.CFuncT)) {
            const sym = vm.valueToTempString(try ivm.getField(decl, symF));
            const symz = try alloc.dupeZ(u8, sym);
            defer alloc.free(symz);
            if (lib.lookup(*anyopaque, symz)) |ptr| {
                // Build function signature.
                ctx.tempTypes.clearRetainingCapacity();
                if (!ctx.config.genMap) {
                    // Self param.
                    try ctx.tempTypes.append(ctx.alloc, bt.Any);
                }

                const ret = try ivm.getField(decl, retf);
                var retType: types.TypeId = undefined;
                if (ret.isObjectType(bt.MetaType)) {
                    const objType = ret.asPointer(*cy.heap.MetaType);
                    retType = objType.symId;
                } else if (ret.isObjectType(os.CArrayT)) {
                    try ctx.ensureArray(ret);
                    retType = bt.List;
                } else {
                    retType = try toSemaType(ivm, ret);
                }

                const cargsv = try ivm.getField(decl, argsf);
                const cargs = cargsv.asPointer(*cy.CyList).items();

                if (cargs.len > 0) {
                    for (cargs) |carg| {
                        if (carg.isObjectType(bt.MetaType)) {
                            const objType = carg.asPointer(*cy.heap.MetaType);
                            try ctx.tempTypes.append(ctx.alloc, objType.symId);
                        } else if (carg.isObjectType(os.CArrayT)) {
                            try ctx.ensureArray(carg);
                            try ctx.tempTypes.append(ctx.alloc, bt.List);
                        } else {
                            try ctx.tempTypes.append(ctx.alloc, try toSemaType(ivm, carg));
                        }
                    }
                }

                const funcSigId = try ivm.sema.ensureFuncSig(ctx.tempTypes.items, retType);
                try cfuncs.append(alloc, .{
                    .decl = decl,
                    .symPtr = ptr,
                    .funcSigId = funcSigId,
                });
            } else {
                log.debug("Missing sym: '{s}'", .{sym});
                return prepareThrowSymbol(vm, .MissingSymbol);
            }
        } else if (decl.isObjectType(os.CStructT)) {
            const val = try ivm.getField(decl, typeF);
            if (!val.isObjectType(bt.MetaType)) {
                log.debug("Not a Symbol", .{});
                return error.InvalidArgument;
            } 
            const objType = val.asPointer(*cy.heap.MetaType);
            if (objType.type != @intFromEnum(cy.heap.MetaTypeKind.object)) {
                log.debug("Not an object Symbol", .{});
                return error.InvalidArgument;
            }
            if (ctx.symToCStructFields.contains(objType.symId)) {
                log.debug("Object type already declared.", .{});
                return error.InvalidArgument;
            }
            const fields = try ivm.getField(decl, fieldsF);
            try ctx.symToCStructFields.put(alloc, objType.symId, fields.asPointer(*cy.CyList));
        } else {
            log.tracev("Not a CFunc or CStruct {} {} {}", .{decl.getTypeId(), os.CFuncT, os.CStructT});
            return error.InvalidArgument;
        }
    }

    // Generate c code.
    var csrc: std.ArrayListUnmanaged(u8) = .{};
    defer csrc.deinit(alloc);
    const w = csrc.writer(alloc);

    try w.print(
        \\#define bool _Bool
        \\#define int64_t long long
        \\#define uint64_t unsigned long long
        // TODO: Check for 32bit addressing.
        \\#define size_t uint64_t
        \\#define int8_t signed char
        \\#define uint8_t unsigned char
        \\#define int16_t short
        \\#define uint16_t unsigned short
        \\#define int32_t int
        \\#define uint32_t unsigned int
        \\#define PointerMask 0xFFFE000000000000
        \\typedef struct UserVM *UserVM;
        \\extern void icyRelease(UserVM*, uint64_t);
        \\extern void* icyGetPtr(uint64_t);
        \\extern uint64_t icyAllocObject(UserVM*, uint32_t);
        \\extern uint64_t icyAllocList(UserVM*, uint64_t*, uint32_t);
        \\extern uint64_t icyAllocCyPointer(UserVM*, void*);
        // \\extern int printf(char* fmt, ...);
        // \\extern void exit(int code);
        \\
    , .{});

    {
        var iter = ctx.symToCStructFields.iterator();
        while (iter.next()) |e| {
            const objSymId = e.key_ptr.*;
            const fields = e.value_ptr.*;

            // Generate C struct.
            try w.print("typedef struct Struct{} {{\n", .{objSymId});
            for (fields.items(), 0..) |field, i| {
                try w.writeAll("  ");
                if (field.isObjectType(os.CArrayT)) {
                    try ctx.ensureArray(field);
                }
                const name = try std.fmt.bufPrint(&Context.buf, "f{}", .{i});
                try ctx.genNamedCType(w, field, name);
                try w.writeAll(";\n");
            }
            try w.print("}} Struct{};\n", .{objSymId});
        }
    }

    // Generate array conversions declarations.
    {
        var iter = ctx.arrays.iterator();
        while (iter.next()) |entry| {
            const carr = entry.value_ptr.*;
            const n: u32 = @intCast((try ivm.getField(carr, ctx.nField)).asInteger());
            const elem = try ivm.getField(carr, ctx.elemField);
            const elemName = try ctx.getTempBaseTypeName(elem);

            // to{elem}Array{n}
            try w.print("void to{s}Array{}(UserVM* vm, uint64_t val, ", .{elemName, n});
            try ctx.genCType(w, elem);
            try w.print("* out);\n", .{});

            // from{elem}Array{n}.
            try w.print("uint64_t from{s}Array{}(UserVM* vm, ", .{elemName, n});
            try ctx.genCType(w, elem);
            try w.print(" arr[{}]);\n", .{n});
        }
    }

    {
        var iter = ctx.symToCStructFields.iterator();
        while (iter.next()) |e| {
            const objSymId = e.key_ptr.*;
            const fields = e.value_ptr.*;
            // Generate to C struct conv.
            try w.print("Struct{} toStruct{}(UserVM* vm, uint64_t val) {{\n", .{objSymId, objSymId});
            // Get pointer to first cyber object field.
            try w.print("  uint64_t* args = (uint64_t*)(val & ~PointerMask) + 1;\n", .{});
            try w.print("  Struct{} res;\n", .{objSymId, });
            for (fields.items(), 0..) |field, i| {
                if (field.isObjectType(os.CArrayT)) {
                    const n: u32 = @intCast((try ivm.getField(field, ctx.nField)).asInteger());
                    const elem = try ivm.getField(field, ctx.elemField);
                    const elemName = try ctx.getTempBaseTypeName(elem);
                    try w.print("  to{s}Array{}(vm, args[{}], &res.f{}[0]);", .{elemName, n, i, i});
                } else {
                    try w.print("  res.f{} = ", .{i});
                    try ctx.genToCValueFromArg(w, field, i);
                    try w.print(";\n", .{});
                }
            }
            try w.print("  return res;\n", .{});
            try w.print("}}\n", .{});

            // Generate from C struct conv.
            try w.print("uint64_t fromStruct{}(UserVM* vm, Struct{} val) {{\n", .{objSymId, objSymId});
            try w.print("  uint64_t obj = icyAllocObject(vm, {});\n", .{objSymId});
            try w.print("  uint64_t* args = (uint64_t*)(obj & ~PointerMask) + 1;\n", .{});
            var buf: [8]u8 = undefined;
            for (fields.items(), 0..) |field, i| {
                if (field.isSymbol()) {
                    const fieldTag = field.asSymbolId();
                    switch (@as(Symbol, @enumFromInt(fieldTag))) {
                        .float => {
                            try w.print("  double arg{} = (double)val.f{};\n", .{i, i});
                            const argStr = try std.fmt.bufPrint(&buf, "arg{}", .{i});
                            try w.print("  args[{}] = ", .{i});
                            try ctx.genToCyValue(w, field, argStr);
                            try w.print(";\n", .{});
                            continue;
                        },
                        else => {},
                    }
                }
                // Int and other types.
                const argStr = try std.fmt.bufPrint(&buf, "val.f{}", .{i});
                try w.print("  args[{}] = ", .{i});
                try ctx.genToCyValue(w, field, argStr);
                try w.print(";\n", .{});
            }
            try w.print("  return obj;\n", .{});
            try w.print("}}\n", .{});

            // Generate ptrTo[Object].
            const isMethod = !config.genMap;
            try w.print("uint64_t cyPtrTo{s}(UserVM* vm, uint64_t* args, char numArgs) {{\n", .{ivm.getTypeName(objSymId)});
            if (isMethod) {
                try w.print("  uint64_t ptr = *((uint64_t*)(args[1] & ~PointerMask) + 1);\n", .{});
            } else {
                try w.print("  uint64_t ptr = *((uint64_t*)(args[0] & ~PointerMask) + 1);\n", .{});
            }
            try w.print("  uint64_t res = fromStruct{}(vm, *(Struct{}*)ptr);\n", .{objSymId, objSymId});
            try w.print("  return res;\n", .{});
            try w.print("}}\n", .{});
        }
    }

    // Generate array conversions.
    {
        var iter = ctx.arrays.iterator();
        while (iter.next()) |entry| {
            const carr = entry.value_ptr.*;
            const n: u32 = @intCast((try ivm.getField(carr, ctx.nField)).asInteger());
            const elem = try ivm.getField(carr, ctx.elemField);
            const elemName = try ctx.getTempBaseTypeName(elem);

            // Generate to{elem}Array{n}. Writes to ptr since arrays can't be returned in C.
            try w.print("void to{s}Array{}(UserVM* vm, uint64_t val, ", .{elemName, n});
            try ctx.genCType(w, elem);
            try w.print("* out) {{\n", .{});
            try w.print("  uint64_t* args = (uint64_t*)*((uint64_t*)(val & ~PointerMask) + 1);\n", .{});
            for (0..n) |i| {
                if (elem.isObjectType(os.CArrayT)) {
                    const subn: u32 = @intCast((try ivm.getField(elem, ctx.nField)).asInteger());
                    const subelem = try ivm.getField(elem, ctx.elemField);
                    const subelemName = try ctx.getTempBaseTypeName(subelem);
                    try w.print("  to{s}Array{}(vm, args[{}], &out[0]);", .{subelemName, subn, i});
                } else {
                    try w.print("  out[{}] = ", .{i});
                    try ctx.genToCValueFromArg(w, elem, i);
                    try w.writeAll(";\n");
                }
            }
            try w.print("}}\n", .{});

            // Generate from{elem}Array{n}.
            try w.print("uint64_t from{s}Array{}(UserVM* vm, ", .{elemName, n});
            try ctx.genCType(w, elem);
            try w.print(" arr[{}]) {{\n", .{n});

            try w.print("  uint64_t vals[{}];\n", .{n});
            for (0..n) |i| {
                try w.print("  vals[{}] = ", .{i});
                const cval = try std.fmt.bufPrint(&Context.buf, "arr[{}]", .{i});
                try ctx.genToCyValue(w, elem, cval);
                try w.writeAll(";\n");
            }
            try w.print("  return icyAllocList(vm, &vals[0], {});\n", .{n});
            try w.print("}}\n", .{});
        }
    }

    // Begin func binding generation.

    for (cfuncs.items) |cfunc| {
        try genCFunc(&ctx, vm, w, cfunc);
    }

    try w.writeByte(0);
    if (DumpCGen) {
        log.debug("{s}", .{csrc.items});
    }

    const state = tcc.tcc_new();
    // Don't include libtcc1.a.
    tcc.tcc_set_options(state, "-nostdlib");
    _ = tcc.tcc_set_output_type(state, tcc.TCC_OUTPUT_MEMORY);

    if (tcc.tcc_compile_string(state, csrc.items.ptr) == -1) {
        cy.panic("Failed to compile c source.");
    }

    // const __floatundisf = @extern(*anyopaque, .{ .name = "__floatundisf", .linkage = .Strong });
    if (builtin.cpu.arch != .aarch64) {
        _ = tcc.tcc_add_symbol(state, "__fixunsdfdi", __fixunsdfdi);
        _ = tcc.tcc_add_symbol(state, "__floatundidf", __floatundidf);
    }
    // _ = tcc.tcc_add_symbol(state, "__floatundisf", __floatundisf);
    // _ = tcc.tcc_add_symbol(state, "printf", std.c.printf);
    // _ = tcc.tcc_add_symbol(state, "exit", std.c.exit);
    // _ = tcc.tcc_add_symbol(state, "breakpoint", breakpoint);
    _ = tcc.tcc_add_symbol(state, "icyRelease", cRelease);
    _ = tcc.tcc_add_symbol(state, "icyGetPtr", cGetPtr);
    _ = tcc.tcc_add_symbol(state, "icyAllocCyPointer", cAllocCyPointer);
    _ = tcc.tcc_add_symbol(state, "icyAllocObject", cAllocObject);
    _ = tcc.tcc_add_symbol(state, "icyAllocList", cAllocList);
    // _ = tcc.tcc_add_symbol(state, "printValue", cPrintValue);
    if (builtin.cpu.arch == .aarch64) {
        _ = tcc.tcc_add_symbol(state, "memmove", memmove);
    }

    // Add binded symbols.
    for (cfuncs.items) |cfunc| {
        const sym = vm.valueToTempString(try ivm.getField(cfunc.decl, symF));
        const symz = try alloc.dupeZ(u8, sym);
        defer alloc.free(symz);
        _ = tcc.tcc_add_symbol(state, symz.ptr, cfunc.symPtr);
    }

    if (tcc.tcc_relocate(state, tcc.TCC_RELOCATE_AUTO) < 0) {
        cy.panic("Failed to relocate compiled code.");
    }


    if (config.genMap) {
        // Create map with binded C-functions as functions.
        const map = vm.allocEmptyMap() catch cy.fatal();

        const cyState = try cy.heap.allocTccState(ivm, state.?, lib);
        cy.arc.retainInc(ivm, cyState, @intCast(cfuncs.items.len + ctx.symToCStructFields.count() - 1));

        for (cfuncs.items) |cfunc| {
            const sym = vm.valueToTempString(try ivm.getField2(cfunc.decl, symF));
            const symGen = try std.fmt.allocPrint(alloc, "cy{s}{u}", .{sym, 0});
            defer alloc.free(symGen);
            const funcPtr = tcc.tcc_get_symbol(state, symGen.ptr) orelse {
                cy.panic("Failed to get symbol.");
            };

            const symKey = vm.retainOrAllocAstring(sym) catch cy.fatal();
            const cargsv = try ivm.getField2(cfunc.decl, argsf);
            const cargs = cargsv.asPointer(*cy.CyList).items();
            const func = cy.ptrAlignCast(*const fn (*cy.UserVM, [*]const Value, u8) Value, funcPtr);

            const funcVal = cy.heap.allocHostFunc(ivm, func, @intCast(cargs.len),
                cfunc.funcSigId, cyState) catch cy.fatal();
            map.asHeapObject().map.set(ivm, symKey, funcVal) catch cy.fatal();
            vm.release(symKey);
            vm.release(funcVal);
        }
        var iter = ctx.symToCStructFields.iterator();
        while (iter.next()) |e| {
            const objSymId = e.key_ptr.*;
            const typeName = ivm.getTypeName(objSymId);
            const symGen = try std.fmt.allocPrint(alloc, "cyPtrTo{s}{u}", .{typeName, 0});
            defer alloc.free(symGen);
            const funcPtr = tcc.tcc_get_symbol(state, symGen.ptr) orelse {
                cy.panic("Failed to get symbol.");
            };

            const symKey = vm.allocAstringConcat("ptrTo", typeName) catch cy.fatal();
            const func = cy.ptrAlignCast(*const fn (*cy.UserVM, [*]const Value, u8) Value, funcPtr);

            const funcSigId = try ivm.sema.ensureFuncSig(&.{bt.Dynamic}, bt.Dynamic);
            const funcVal = cy.heap.allocHostFunc(ivm, func, 1, funcSigId, cyState) catch cy.fatal();
            map.asHeapObject().map.set(ivm, symKey, funcVal) catch cy.fatal();
            vm.release(symKey);
            vm.release(funcVal);
        }
        success = true;
        return map;
    } else {
        // Create anonymous struct with binded C-functions as methods.
        const osSym = ivm.compiler.chunkMap.get("os").?.sym;
        const sid = try ivm.addAnonymousStruct(@ptrCast(osSym), "BindLib", os.nextUniqId, &.{ "tcc" });
        os.nextUniqId += 1;
        const tccField = try ivm.ensureFieldSym("tcc");
        try ivm.addFieldSym(sid, tccField, 0, bt.Any);

        const cyState = try cy.heap.allocTccState(ivm, state.?, lib);
        for (cfuncs.items) |cfunc| {
            const sym = vm.valueToTempString(try ivm.getField2(cfunc.decl, symF));
            const cySym = try std.fmt.allocPrint(alloc, "cy{s}{u}", .{sym, 0});
            defer alloc.free(cySym);
            const funcPtr = tcc.tcc_get_symbol(state, cySym.ptr) orelse {
                cy.panic("Failed to get symbol.");
            };

            const cargsv = try ivm.getField2(cfunc.decl, argsf);
            const cargs = cargsv.asPointer(*cy.CyList).items();

            const func = cy.ptrAlignCast(cy.ZHostFuncFn, funcPtr);

            const mgId = try ivm.ensureMethodGroup(sym);
            try @call(.never_inline, cy.VM.addMethod, .{ivm, sid, mgId, rt.MethodInit.initHostTyped(cfunc.funcSigId, func, @as(u8, @intCast(cargs.len)) + 1) });
        }
        var iter = ctx.symToCStructFields.iterator();
        while (iter.next()) |e| {
            const objSymId = e.key_ptr.*;
            const entry = ivm.types[objSymId];
            const typeName = entry.sym.name();
            const symGen = try std.fmt.allocPrint(alloc, "cyPtrTo{s}{u}", .{typeName, 0});
            defer alloc.free(symGen);
            const funcPtr = tcc.tcc_get_symbol(state, symGen.ptr) orelse {
                cy.panic("Failed to get symbol.");
            };
            const func = cy.ptrAlignCast(cy.ZHostFuncFn, funcPtr);

            const methodName = try std.fmt.allocPrint(alloc, "ptrTo{s}", .{typeName});
            defer alloc.free(methodName);
            const mgId = try ivm.ensureMethodGroup2(methodName, true);
            const funcSigId = try ivm.sema.ensureFuncSig(&.{ bt.Any, bt.Pointer }, objSymId);
            try @call(.never_inline, cy.VM.addMethod, .{ivm, sid, mgId, rt.MethodInit.initHostTyped(funcSigId, func, 2) });
        }
        success = true;
        return try vm.allocObjectSmall(sid, &.{cyState});
    }
}

const CFuncData = struct {
    decl: Value,
    symPtr: *anyopaque,
    funcSigId: cy.sema.FuncSigId,
};

fn genCFunc(ctx: *Context, vm: *cy.UserVM, w: anytype, cfunc: CFuncData) !void {
    const ivm = vm.internal();
    const symF = try ivm.ensureFieldSym("sym");
    const argsf = try ivm.ensureFieldSym("args");
    const retf = try ivm.ensureFieldSym("ret");
    const sym = vm.valueToTempString(try ivm.getField(cfunc.decl, symF));
    const cargsv = try ivm.getField(cfunc.decl, argsf);
    const ret = try ivm.getField(cfunc.decl, retf);

    const cargs = cargsv.asPointer(*cy.CyList).items();

    // Emit extern declaration.
    try w.writeAll("extern ");
    try ctx.genCType(w, ret);
    try w.print(" {s}(", .{ sym });
    if (cargs.len > 0) {
        const lastArg = cargs.len-1;
        for (cargs, 0..) |carg, i| {
            try ctx.genCType(w, carg);
            if (i != lastArg) {
                try w.print(", ", .{});
            }
        }
    }
    try w.print(");\n", .{});

    const isMethod = !ctx.config.genMap;
    try w.print("uint64_t cy{s}(UserVM* vm, uint64_t* args, char numArgs) {{\n", .{sym});
    if (isMethod) {
        try w.print("  uint64_t recv = args[0];\n", .{});
    }
    // w.print("  printF64(*(double*)&args[0]);\n", .{}) catch cy.fatal();

    // Temps.
    if (cargs.len > 0) {
        for (cargs, 0..) |carg, i| {
            const argIdx = if (isMethod) i + 1 else i;
            if (carg.isObjectType(os.CArrayT)) {
                const n: u32 = @intCast((try ivm.getField(carg, ctx.nField)).asInteger());
                const elem = try ivm.getField(carg, ctx.elemField);
                const elemName = try ctx.getTempBaseTypeName(elem);

                try w.print("  ", .{});
                const cval = try std.fmt.bufPrint(&Context.buf, "arr{}", .{argIdx});
                try ctx.genNamedCType(w, carg, cval);
                try w.print(";\n", .{});

                try w.print("  to{s}Array{}(vm, args[{}], &arr{}[0]);", .{elemName, n, argIdx, argIdx});
            } else {
                continue;
            }
        }
    }

    // Gen call.
    if (ret.isObjectType(bt.MetaType)) {
        const objType = ret.asPointer(*cy.heap.MetaType);
        if (ctx.symToCStructFields.contains(objType.symId)) {
            try w.print("  Struct{} res = {s}(", .{objType.symId, sym});
        } else {
            log.debug("CStruct not declared.", .{});
            return error.InvalidArgument;
        }
    } else {
        const retTag = ret.asSymbolId();
        switch (@as(Symbol, @enumFromInt(retTag))) {
            .char => {
                try w.print("  int8_t res = {s}(", .{sym});
            },
            .uchar => {
                try w.print("  uint8_t res = {s}(", .{sym});
            },
            .short => {
                try w.print("  int16_t res = {s}(", .{sym});
            },
            .ushort => {
                try w.print("  uint16_t res = {s}(", .{sym});
            },
            .int => {
                try w.print("  int32_t res = {s}(", .{sym});
            },
            .uint => {
                try w.print("  uint32_t res = {s}(", .{sym});
            },
            .long => {
                try w.print("  int64_t res = {s}(", .{sym});
            },
            .ulong => {
                try w.print("  uint64_t res = {s}(", .{sym});
            },
            .usize => {
                try w.print("  size_t res = {s}(", .{sym});
            },
            .float => {
                try w.print("  double res = (double){s}(", .{sym});
            },
            .double => {
                try w.print("  double res = {s}(", .{sym});
            },
            .charPtr => {
                try w.print("  char* res = {s}(", .{sym});
            },
            .voidPtr => {
                try w.print("  void* res = {s}(", .{sym});
            },
            .void => {
                try w.print("  {s}(", .{sym});
            },
            .bool => {
                try w.print("  bool res = {s}(", .{sym});
            },
            else => cy.panicFmt("Unsupported return type: {s}", .{ ivm.getSymbolName(retTag) }),
        }
    }

    // Gen args.
    if (cargs.len > 0) {
        const lastArg = cargs.len-1;
        for (cargs, 0..) |carg, i| {
            const argIdx = if (isMethod) i + 1 else i;
            if (carg.isObjectType(os.CArrayT)) {
                try w.print("arr{}", .{argIdx});
            } else {
                try ctx.genToCValueFromArg(w, carg, argIdx);
            }
            if (i != lastArg) {
                try w.print(", ", .{});
            }
        }
    }

    // End of args.
    try w.print(");\n", .{});

    // Gen return.
    try w.print("  return ", .{});
    try ctx.genToCyValue(w, ret, "res");
    try w.print(";\n", .{});

    try w.print("}}\n", .{});
}

fn dlopen(path: []const u8) !std.DynLib {
    if (builtin.os.tag == .linux and builtin.link_libc) {
        const path_c = try std.os.toPosixPath(path);
        // Place the lookup scope of the symbols in this library ahead of the global scope.
        const RTLD_DEEPBIND = 0x00008;
        return std.DynLib{
            .handle = std.os.system.dlopen(&path_c, std.os.system.RTLD.LAZY | RTLD_DEEPBIND) orelse {
                return error.FileNotFound;
            }
        };
    } else {
        return std.DynLib.open(path);
    }
}

extern fn __floatundidf(u64) f64;
extern fn __fixunsdfdi(f64) u64;
extern fn memmove(dst: *anyopaque, src: *anyopaque, num: usize) *anyopaque;

fn cRelease(vm: *cy.UserVM, val: Value) callconv(.C) void {
    vm.release(val);
}

fn cGetPtr(val: Value) callconv(.C) ?*anyopaque {
    return val.asPointer(*cy.Pointer).ptr;
}

fn cAllocCyPointer(vm: *cy.UserVM, ptr: ?*anyopaque) callconv(.C) Value {
    return cy.heap.allocPointer(vm.internal(), ptr) catch cy.fatal();
}

fn cAllocObject(vm: *cy.UserVM, id: u32) callconv(.C) Value {
    const ivm = vm.internal();

    const numFields = ivm.compiler.sema.types.items[id].data.numFields;
    if (numFields <= 4) {
        return cy.heap.allocEmptyObjectSmall(ivm, id) catch cy.fatal();
    } else {
        return cy.heap.allocEmptyObject(ivm, id, numFields) catch cy.fatal();
    }
}

fn cAllocList(vm: *cy.UserVM, elems: [*]Value, n: u32) callconv(.C) Value {
    const ivm = vm.internal();
    return cy.heap.allocList(ivm, elems[0..n]) catch cy.fatal();
}

fn cPrintValue(val: u64) void {
    const v: Value = @bitCast(val);
    v.dump();
}

fn breakpoint() callconv(.C) void {
    @breakpoint();
}
