module rewind.re.dynasm.arm64;

import core.sys.posix.sys.mman : mmap, munmap, mprotect, PROT_READ, PROT_WRITE, PROT_EXEC, MAP_PRIVATE, MAP_ANON, MAP_FAILED;
import std.exception : enforce;
import std.stdio : writeln;

// LLVM/GCC intrinsic for instruction cache flushing (critical for ARM64 JITs)
extern(C) void __clear_cache(char* begin, char* end);

// --- Operand Types ---
enum RegSize { W = 0, X = 1 }

struct Register {
    uint id;
    RegSize size;
}

struct Immediate {
    uint value;
}

struct Label {
    int offset = -1; // -1 indicates the label is not yet bound
    uint id;
}

// --- Addressing Mode Structs ---

struct MemImm {
    Register base;
    int offset; // Byte offset
}

struct MemPre {
    Register base;
    int offset; // Byte offset
}

struct MemPost {
    Register base;
    int offset; // Byte offset
}

enum ExtendType { 
    UXTW = 0b010, // Zero-extend 32-bit to 64-bit
    LSL  = 0b011, // Shift (or UXTX for 64-bit registers)
    SXTW = 0b110, // Sign-extend 32-bit to 64-bit
    SXTX = 0b111  // Sign-extend 64-bit to 64-bit
}

struct MemReg {
    Register base;
    Register offset;
    ExtendType ext;
    bool shift; // If true, shifts the offset by log2(access_size)
}

enum Condition {
    EQ = 0x0, // Equal
    NE = 0x1, // Not Equal
    CS = 0x2, // Carry Set (Greater than or equal, unsigned)
    HS = 0x2, // Higher or Same (Synonym for CS)
    CC = 0x3, // Carry Clear (Less than, unsigned)
    LO = 0x3, // Lower (Synonym for CC)
    MI = 0x4, // Minus (Negative)
    PL = 0x5, // Plus (Positive or zero)
    VS = 0x6, // Overflow Set
    VC = 0x7, // Overflow Clear
    HI = 0x8, // Higher (unsigned >)
    LS = 0x9, // Lower or Same (unsigned <=)
    GE = 0xA, // Greater than or Equal (signed)
    LT = 0xB, // Less than (signed)
    GT = 0xC, // Greater than (signed)
    LE = 0xD, // Less than or Equal (signed)
    AL = 0xE  // Always
}

// --- DSL Helpers ---

/// Unsigned immediate offset (e.g., [Xn, #16])
MemImm mem(Register base, int offset = 0) { return MemImm(base, offset); }

/// Pre-indexed memory access (e.g., [Xn, #16]!)
MemPre pre(Register base, int offset) { return MemPre(base, offset); }

/// Post-indexed memory access (e.g., [Xn], #16)
MemPost post(Register base, int offset) { return MemPost(base, offset); }

/// Register offset memory access (e.g., [Xn, Xm, LSL #3])
MemReg mem(Register base, Register offset, ExtendType ext = ExtendType.LSL, bool shift = false) {
    return MemReg(base, offset, ext, shift);
}


// Helper methods for clean DSL-like operand initialization
Immediate imm(uint val) { return Immediate(val); }
Register x(uint id) { return Register(id, RegSize.X); }
Register w(uint id) { return Register(id, RegSize.W); }

// --- Assembler Struct ---
struct Assembler {
    private {
        uint* buffer;
        size_t capacity;
        size_t count; // Current instruction count (word offset)
        
        enum FixupKind : ubyte {
            B,
            BCond,
            ADR,
            LdrLit64,
        }

        struct Fixup {
            uint instrOffset; // Word offset of the branch instruction
            uint labelId;     // ID of the unbound label
            FixupKind kind;
        }
        
        Fixup[] fixups;
        uint nextLabelId = 1;
    }

    this(size_t sizeInBytes) {
        capacity = sizeInBytes / uint.sizeof;
        
        // Map as Read & Write first (W^X best practices)
        buffer = cast(uint*)mmap(null, sizeInBytes, 
                                 PROT_READ | PROT_WRITE, 
                                 MAP_PRIVATE | MAP_ANON, -1, 0);
        enforce(buffer != MAP_FAILED, "mmap failed to allocate JIT buffer");
    }

    @disable this(this); // Prevent copying to safely manage mmap lifecycle

    ~this() {
        /*if (buffer) {
            munmap(buffer, capacity * uint.sizeof);
        }*/
    }

    /// Transitions memory from Writable to Executable and flushes I-Cache
    void finalize() {
        int res = mprotect(buffer, capacity * uint.sizeof, PROT_READ | PROT_EXEC);
        enforce(res == 0, "mprotect failed to set PROT_EXEC");

        // ARM64 has separate data and instruction caches. 
        // This builtin flushes the cache lines to prevent executing stale data.
        __clear_cache(cast(char*)buffer, cast(char*)(buffer + count));
    }

    /// Slice of encoded instructions so far
    uint[] data() {
        return buffer[0..count];
    }

    /// Casts the internal buffer to a callable C-style function pointer
    long function() getFunction() {
        return cast(long function())buffer;
    }

    // --- Label Resolution ---
    
    Label createLabel() {
        return Label(-1, nextLabelId++);
    }

    /// Anchors the label to the current instruction offset and resolves any pending jumps
    void bind(ref Label lbl) {
        enforce(lbl.offset == -1, "Label is already bound");
        lbl.offset = cast(int)count;
        
        // Resolve forward references
        foreach (ref f; fixups) {
            if (f.labelId == lbl.id) {
                patchFixup(f, lbl.offset);
            }
        }
    }

    private void emit(uint instr) {
        enforce(count < capacity, "Assembler buffer overflow");
        buffer[count++] = instr;
    }

    // --- Instruction Encodings (Overloaded by Operands) ---

    /// MOVZ - Move 16-bit immediate to register
    void mov(Register rd, Immediate im) {
        uint sf = (rd.size == RegSize.X) ? 1 : 0;
        uint imm16 = im.value & 0xFFFF;
        // Encoding: sf(31) 10 100101 00(hw) imm16(20:5) Rd(4:0)
        emit((sf << 31) | 0x52800000 | (imm16 << 5) | rd.id);
    }

    /// MOV (Register) - Implemented via ORR Rd, XZR, Rm
    void mov(Register rd, Register rm) {
        uint sf = (rd.size == RegSize.X) ? 1 : 0;
        // Encoding: sf(31) 0101010 00000 Rm(20:16) 000000 Rn(9:5) Rd(4:0)
        // Note: Register 31 is the Zero Register (XZR/WZR) in this context
        emit((sf << 31) | 0x2A000000 | (rm.id << 16) | (31 << 5) | rd.id);
    }

    /// ADD - Register addition
    void add(Register rd, Register rn, Register rm) {
        uint sf = (rd.size == RegSize.X) ? 1 : 0;
        // Encoding: sf(31) 000 1011 0000 Rm(20:16) 000000 Rn(9:5) Rd(4:0)
        emit((sf << 31) | 0x0B000000 | (rm.id << 16) | (rn.id << 5) | rd.id);
    }

    /// ADD - With immediate
    void add(Register rd, Register rn, Immediate imm) {
        enforce(rd.size == RegSize.X, "this add-immediate is for X regs");
        enforce(imm.value <= 0xFFF, "imm12 out of range");

        uint sf    = 1;
        uint sh    = 0;          
        uint imm12 = imm.value;  

        // Encoding: sf(31) | op(30)=0 | S(29)=0 | 100010 (28..23)
        //           | sh(22) | imm12(21..10) | Rn(9..5) | Rd(4..0)
        uint instr = (sf << 31) | 0x11000000 | (sh << 22) |
                    (imm12 << 10) | (rn.id << 5) | rd.id;
        emit(instr);
    }

    /// B - Unconditional Branch
    void b(ref Label lbl) {
        if (lbl.offset == -1) {
            // Forward reference: Save fixup offset, emit a dummy placeholder
            fixups ~= Fixup(cast(uint)count, lbl.id, FixupKind.B);
            emit(0x14000000); 
        } else {
            // Backward reference: Emit with immediate offset
            emitBranch(lbl.offset);
        }
    }

    /// RET - Return from subroutine (Defaults to X30)
    void ret(Register rn = Register(30, RegSize.X)) {
        // Encoding: 1101 0110 0101 1111 0000 0000 0000 0000
        emit(0xD65F0000 | (rn.id << 5));
    }

    void adr(Register rd, ref Label lbl) {
        enforce(rd.size == RegSize.X, "ADR requires an X register");

        if (lbl.offset == -1) {
            fixups ~= Fixup(cast(uint)count, lbl.id, FixupKind.ADR);
            emit(0x10000000 | rd.id); // placeholder, Rd already encoded
        } else {
            emitAdr(rd, lbl.offset);
        }
    }

    private void emitAdr(Register rd, int targetOffset) {
        int diffInstrs = targetOffset - cast(int)count;
        long diffBytes = cast(long)diffInstrs * 4;

        enforce(diffBytes >= -(1 << 20) && diffBytes < (1 << 20),
                "ADR target out of range (+/-1MB)");

        uint imm = cast(uint)diffBytes & 0x1FFFFF;
        uint immlo = imm & 0x3;
        uint immhi = imm >> 2;

        emit(0x10000000 | (immlo << 29) | (immhi << 5) | rd.id);
    }

    // --- Branch Resolution Internals ---

    private void emitBranch(int targetOffset) {
        int diff = targetOffset - cast(int)count;
        uint imm26 = diff & 0x03FFFFFF; // Mask to 26 bits
        emit(0x14000000 | imm26);
    }

    private uint getSizeBits(Register r) {
        return (r.size == RegSize.X) ? 3 : 2; // 3 for 64-bit (X), 2 for 32-bit (W)
    }

    private uint getScale(Register r) {
        return (r.size == RegSize.X) ? 8 : 4;
    }

    // ==========================================
    // LDR (Load Register)
    // ==========================================

    /// LDR - Unsigned Immediate Scaled Offset
    void ldr(Register rt, MemImm m) {
        uint sz = getSizeBits(rt);
        uint scale = getScale(rt);
        enforce(m.offset >= 0, "Scaled immediate must be >= 0");
        enforce(m.offset % scale == 0, "Scaled immediate must be aligned to access size");
        uint imm12 = (m.offset / scale) & 0xFFF;
        // Encoding: size(31:30) 11 1001 01 imm12(21:10) Rn(9:5) Rt(4:0)
        emit((sz << 30) | 0x39400000 | (imm12 << 10) | (m.base.id << 5) | rt.id);
    }

    /// LDR - Pre-indexed
    void ldr(Register rt, MemPre m) {
        uint sz = getSizeBits(rt);
        enforce(m.offset >= -256 && m.offset <= 255, "Pre-index offset must be between -256 and 255");
        uint imm9 = m.offset & 0x1FF;
        // Encoding: size(31:30) 11 1000 010 imm9(20:12) 11 Rn(9:5) Rt(4:0)
        emit((sz << 30) | 0x38400C00 | (imm9 << 12) | (m.base.id << 5) | rt.id);
    }

    /// LDR - Post-indexed
    void ldr(Register rt, MemPost m) {
        uint sz = getSizeBits(rt);
        enforce(m.offset >= -256 && m.offset <= 255, "Post-index offset must be between -256 and 255");
        uint imm9 = m.offset & 0x1FF;
        // Encoding: size(31:30) 11 1000 010 imm9(20:12) 01 Rn(9:5) Rt(4:0)
        emit((sz << 30) | 0x38400400 | (imm9 << 12) | (m.base.id << 5) | rt.id);
    }

    /// LDR - Register Offset
    void ldr(Register rt, MemReg m) {
        uint sz = getSizeBits(rt);
        uint S = m.shift ? 1 : 0;
        // Encoding: size(31:30) 11 1000 011 Rm(20:16) option(15:13) S(12) 10 Rn(9:5) Rt(4:0)
        emit((sz << 30) | 0x38600800 | (m.offset.id << 16) | (m.ext << 13) | (S << 12) | (m.base.id << 5) | rt.id);
    }

    void ldr(Register rt, ref Label lbl) {
        enforce(rt.size == RegSize.X, "ldr label requires an X register");

        if (lbl.offset == -1) {
            fixups ~= Fixup(cast(uint)count, lbl.id, FixupKind.LdrLit64);
            emit(0x58000000 | rt.id); // placeholder, Rt already encoded
        } else {
            emitLdrLit(rt, lbl.offset);
        }
    }

    private void emitLdrLit(Register rt, int targetOffset) {
        int diffInstrs = targetOffset - cast(int)count;

        enforce(diffInstrs >= -(1 << 18) && diffInstrs < (1 << 18),
                "LDR literal target out of range (+/-1MB, word-scaled)");

        uint imm19 = cast(uint)diffInstrs & 0x7FFFF;
        emit(0x58000000 | (imm19 << 5) | rt.id);
    }

    // ==========================================
    // LDRB - Load byte, zero-extend into Wt
    // ==========================================

    void ldrb(Register rt, MemImm m) {
        requireW(rt, "ldrb");
        enforce(m.offset >= 0 && m.offset <= 4095,
                "LDRB unsigned offset must be in range 0..4095");
        uint imm12 = cast(uint)m.offset;
        // Base opcode for LDRB unsigned offset
        emit(0x39400000 | (imm12 << 10) | (m.base.id << 5) | rt.id);
    }

    void ldrb(Register rt, MemPre m) {
        requireW(rt, "ldrb");
        enforce(m.offset >= -256 && m.offset <= 255,
                "LDRB pre-index offset must be in range -256..255");
        uint imm9 = cast(uint)m.offset & 0x1FF;
        // Base opcode for LDRB pre-index
        emit(0x38400C00 | (imm9 << 12) | (m.base.id << 5) | rt.id);
    }

    void ldrb(Register rt, MemPost m) {
        requireW(rt, "ldrb");
        enforce(m.offset >= -256 && m.offset <= 255,
                "LDRB post-index offset must be in range -256..255");
        uint imm9 = cast(uint)m.offset & 0x1FF;
        // Base opcode for LDRB post-index
        emit(0x38400400 | (imm9 << 12) | (m.base.id << 5) | rt.id);
    }

    void ldrb(Register rt, MemReg m) {
        requireW(rt, "ldrb");

        // For byte loads, shift-by-access-size is shift-by-0, so force false or ignore it.
        enforce(!m.shift, "LDRB register-offset does not need scaled shift");

        // Base opcode for LDRB register offset
        emit(0x38600800 |
            (m.offset.id << 16) |
            (cast(uint)m.ext << 13) |
            (m.base.id << 5) |
            rt.id);
    }

    // ==========================================
    // STR (Store Register)
    // ==========================================

    /// STR - Unsigned Immediate Scaled Offset
    void str(Register rt, MemImm m) {
        uint sz = getSizeBits(rt);
        uint scale = getScale(rt);
        enforce(m.offset >= 0 && m.offset % scale == 0, "Invalid scaled immediate offset");
        uint imm12 = (m.offset / scale) & 0xFFF;
        // Encoding: size(31:30) 11 1001 00 imm12(21:10) Rn(9:5) Rt(4:0)
        emit((sz << 30) | 0x39000000 | (imm12 << 10) | (m.base.id << 5) | rt.id);
    }

    /// STR - Pre-indexed
    void str(Register rt, MemPre m) {
        uint sz = getSizeBits(rt);
        enforce(m.offset >= -256 && m.offset <= 255, "Invalid pre-index offset");
        uint imm9 = m.offset & 0x1FF;
        // Encoding: size(31:30) 11 1000 000 imm9(20:12) 11 Rn(9:5) Rt(4:0)
        emit((sz << 30) | 0x38000C00 | (imm9 << 12) | (m.base.id << 5) | rt.id);
    }

    /// STR - Post-indexed
    void str(Register rt, MemPost m) {
        uint sz = getSizeBits(rt);
        enforce(m.offset >= -256 && m.offset <= 255, "Invalid post-index offset");
        uint imm9 = m.offset & 0x1FF;
        // Encoding: size(31:30) 11 1000 000 imm9(20:12) 01 Rn(9:5) Rt(4:0)
        emit((sz << 30) | 0x38000400 | (imm9 << 12) | (m.base.id << 5) | rt.id);
    }

    /// STR - Register Offset
    void str(Register rt, MemReg m) {
        uint sz = getSizeBits(rt);
        uint S = m.shift ? 1 : 0;
        // Encoding: size(31:30) 11 1000 001 Rm(20:16) option(15:13) S(12) 10 Rn(9:5) Rt(4:0)
        emit((sz << 30) | 0x38200800 | (m.offset.id << 16) | (m.ext << 13) | (S << 12) | (m.base.id << 5) | rt.id);
    }

        // ==========================================
    // CMP (Compare)
    // ==========================================

    /// CMP - Register with Register
    void cmp(Register rn, Register rm) {
        uint sf = (rn.size == RegSize.X) ? 1 : 0;
        // Encoding: sf(31) 110 1011 0000 Rm(20:16) 000000 Rn(9:5) Rd(4:0)
        // Rd is 31 (Zero Register) to discard the result and only set flags
        emit((sf << 31) | 0x6B000000 | (rm.id << 16) | (rn.id << 5) | 31);
    }

    /// CMP - Register with Immediate
    void cmp(Register rn, Immediate im) {
        uint sf = (rn.size == RegSize.X) ? 1 : 0;
        uint imm12 = im.value & 0xFFF; // Supports 12-bit unsigned immediate
        // Encoding: sf(31) 111 0001 0 00(shift) imm12(21:10) Rn(9:5) Rd(4:0)
        emit((sf << 31) | 0x71000000 | (imm12 << 10) | (rn.id << 5) | 31);
    }

    // ==========================================
    // B.cond (Conditional Branch)
    // ==========================================

    /// B.cond - Conditional Branch
    void b(Condition cond, ref Label lbl) {
        if (lbl.offset == -1) {
            // Forward reference: Save fixup offset, emit a dummy placeholder
            // Include the condition code in the dummy instruction so patchBranch preserves it
            fixups ~= Fixup(cast(uint)count, lbl.id, FixupKind.BCond);
            emit(0x54000000 | cond); 
        } else {
            // Backward reference: Emit with immediate offset
            emitCondBranch(cond, lbl.offset);
        }
    }

    void br(Register rn) {
        // Encoding: 1101 0110 0000 1111 0000 0000 0000 Rn
        //          31..21       20..5                      4..0
        enforce(rn.size == RegSize.X, "BR requires an X register");
        emit(0xD61F0000 | (rn.id << 5));
    }

    /// BLR Xn -- indirect call (branch with link to register)
    void blr(Register rn) {
        // Encoding: 1101 0110 0001 1111 0000 0000 0000 Rn
        enforce(rn.size == RegSize.X, "BLR requires an X register");
        emit(0xD63F0000 | (rn.id << 5));
    }

    private void requireW(Register rt, string op) {
        enforce(rt.size == RegSize.W, op ~ " requires a W register destination");
    }

    private void emitCondBranch(Condition cond, int targetOffset) {
        int diff = targetOffset - cast(int)count;
        uint imm19 = diff & 0x0007FFFF; // Mask to 19 bits
        // Encoding: 01010100 imm19(23:5) 0 cond(3:0)
        emit(0x54000000 | (imm19 << 5) | cond);
    }

    private void patchFixup(Fixup f, int targetOffset) {
        uint instr = buffer[f.instrOffset];
        int diffInstrs = targetOffset - cast(int)f.instrOffset;

        final switch (f.kind) {
        case FixupKind.B:
            enforce(diffInstrs >= -(1 << 25) && diffInstrs < (1 << 25),
                    "B target out of range");
            uint imm26 = cast(uint)diffInstrs & 0x03FF_FFFF;
            buffer[f.instrOffset] = (instr & 0xFC00_0000) | imm26;
            break;

        case FixupKind.BCond:
            enforce(diffInstrs >= -(1 << 18) && diffInstrs < (1 << 18),
                    "B.cond target out of range");
            uint imm19 = cast(uint)diffInstrs & 0x7FFFF;
            buffer[f.instrOffset] = (instr & 0xFF00_001F) | (imm19 << 5);
            break;

        case FixupKind.ADR:
            long diffBytes = cast(long)diffInstrs * 4;
            enforce(diffBytes >= -(1 << 20) && diffBytes < (1 << 20),
                    "ADR target out of range");
            uint imm = cast(uint)diffBytes & 0x1F_FFFF;
            uint immlo = imm & 0x3;
            uint immhi = imm >> 2;
            buffer[f.instrOffset] =
                (instr & 0x9F00_001F) |   // preserve op bits and Rd
                (immlo << 29) |
                (immhi << 5);
            break;

        case FixupKind.LdrLit64:
            enforce(diffInstrs >= -(1 << 18) && diffInstrs < (1 << 18),
                    "LDR literal target out of range");
            uint imm19 = cast(uint)diffInstrs & 0x7FFFF;
            buffer[f.instrOffset] =
                (instr & 0xFF00_001F) |   // preserve opcode and Rt
                (imm19 << 5);
            break;
        }
    }
}


unittest {
    auto assembler = Assembler(16 * 1024);
    with(assembler) {
        auto lbl = createLabel();
        mov(x(2), imm(256));
        mov(x(1), x(2));
        bind(lbl);
        add(x(2), x(11), x(12));
        b(lbl);
    }
    import std.file;
    std.file.write("data.bin", cast(ubyte[])assembler.data);
}