module rewind.re.dynasm.arm64;

import core.sys.posix.sys.mman : mmap, munmap, mprotect, PROT_READ, PROT_WRITE, PROT_EXEC, MAP_PRIVATE, MAP_ANON, MAP_FAILED;
import std.exception : enforce;
import std.stdio : writeln;

// LLVM/GCC intrinsic for instruction cache flushing (critical for ARM64 JITs)
extern(C) void __builtin___clear_cache(char* begin, char* end);

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
Memory mem(Register base, uint scaledOffset = 0) { return Memory(base, scaledOffset); }

// --- Assembler Struct ---
struct Assembler {
    private {
        uint* buffer;
        size_t capacity;
        size_t count; // Current instruction count (word offset)
        
        struct Fixup {
            uint instrOffset; // Word offset of the branch instruction
            uint labelId;     // ID of the unbound label
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
        if (buffer) {
            munmap(buffer, capacity * uint.sizeof);
        }
    }

    /// Transitions memory from Writable to Executable and flushes I-Cache
    void finalize() {
        int res = mprotect(buffer, capacity * uint.sizeof, PROT_READ | PROT_EXEC);
        enforce(res == 0, "mprotect failed to set PROT_EXEC");

        // ARM64 has separate data and instruction caches. 
        // This builtin flushes the cache lines to prevent executing stale data.
        __builtin___clear_cache(cast(char*)buffer, cast(char*)(buffer + count));
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
                patchBranch(f.instrOffset, lbl.offset);
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

    /// LDR - Load register from memory (Unsigned immediate offset)
    void ldr(Register rt, Memory m) {
        uint size = (rt.size == RegSize.X) ? 3 : 2;
        uint imm12 = m.scaledOffset & 0xFFF;
        // Encoding: size(31:30) 11 1001 01 imm12(21:10) Rn(9:5) Rt(4:0)
        emit((size << 30) | 0x39400000 | (imm12 << 10) | (m.base.id << 5) | rt.id);
    }

    /// B - Unconditional Branch
    void b(ref Label lbl) {
        if (lbl.offset == -1) {
            // Forward reference: Save fixup offset, emit a dummy placeholder
            fixups ~= Fixup(cast(uint)count, lbl.id);
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

    // --- Branch Resolution Internals ---

    private void emitBranch(int targetOffset) {
        int diff = targetOffset - cast(int)count;
        uint imm26 = diff & 0x03FFFFFF; // Mask to 26 bits
        emit(0x14000000 | imm26);
    }

    private void patchBranch(uint instrOffset, int targetOffset) {
        int diff = targetOffset - cast(int)instrOffset;
        uint instr = buffer[instrOffset];
        
        if ((instr & 0xFC000000) == 0x14000000) { 
            // It's an Unconditional Branch (B)
            // Range: ±32MB (26 bits)
            uint imm26 = diff & 0x03FFFFFF;
            buffer[instrOffset] = (instr & 0xFC000000) | imm26;
        } 
        else if ((instr & 0xFF000000) == 0x54000000) { 
            // It's a Conditional Branch (B.cond)
            // Range: ±1MB (19 bits)
            uint imm19 = diff & 0x0007FFFF;
            // 0xFF00001F masks out the old immediate but preserves the opcode (top 8) and condition (bottom 5)
            buffer[instrOffset] = (instr & 0xFF00001F) | (imm19 << 5);
        } 
        else {
            enforce(false, "Unsupported branch instruction encountered during fixup");
        }
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
            fixups ~= Fixup(cast(uint)count, lbl.id);
            emit(0x54000000 | cond); 
        } else {
            // Backward reference: Emit with immediate offset
            emitCondBranch(cond, lbl.offset);
        }
    }

    private void emitCondBranch(Condition cond, int targetOffset) {
        int diff = targetOffset - cast(int)count;
        uint imm19 = diff & 0x0007FFFF; // Mask to 19 bits
        // Encoding: 01010100 imm19(23:5) 0 cond(3:0)
        emit(0x54000000 | (imm19 << 5) | cond);
    }
}
