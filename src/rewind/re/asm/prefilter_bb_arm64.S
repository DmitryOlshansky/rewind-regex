#define INPUT x0
#define END_INPUT x1
#define FIRST w2
#define LAST w3
#define LEN x4
#define OFFSET x5
#define PTR x6
#define V_INPUT_END x7
#define SCRATCH x8
#define SCRATCH_W w8
#define MASK    x9
#define RES_SCALAR x10
#define SCALAR_PTR x11

#define FIRST_V v0.16b
#define LAST_V v1.16b
#define BYTES v2.16b
#define BYTES_Q q2
#define RES v3.16b
#define RES_W v3.4s
#define RES_LOW v3.8b
#define RES2 v4.16b
#define RES2_W v4.4s
#define BITS_TABLE v5.16b

#ifdef __APPLE__
.global _rewindRePrefilterBB
_rewindRePrefilterBB:
    adrp    SCRATCH, .bit_weights@GOTPAGE
    ldr     SCRATCH, [SCRATCH, .bit_weights@GOTPAGEOFF]
 #else
.global rewindRePrefilterBB
rewindRePrefilterBB:
    adrp    SCRATCH, .bit_weights
    add     SCRATCH, SCRATCH, :lo12:.bit_weights
 #endif 
    ld1     {BITS_TABLE}, [SCRATCH]
    mov     PTR, INPUT
    sub     V_INPUT_END, END_INPUT, LEN
    movn    SCRATCH, #15
    and     V_INPUT_END, V_INPUT_END, SCRATCH
    sub     OFFSET, LEN, #17  // offset is relative to (addr+16) postincremented: len - 16
    dup     FIRST_V, FIRST
    dup     LAST_V, LAST
loop_vector:
    cmp     PTR, V_INPUT_END
    b.eq    scalar
    ld1     {BYTES}, [PTR], #16
    cmeq    RES, BYTES, FIRST_V
    
    ldr     BYTES_Q, [PTR, OFFSET]
    cmeq    RES2, BYTES, LAST_V
    and     RES, RES, RES2
    umaxv   s11, RES_W
    fmov    w11, s11
    cbz     w11, loop_vector

    and     RES, RES, BITS_TABLE
    uaddlv  h12, RES_LOW
    ext     RES, RES, RES, #8
    uaddlv  h13, RES_LOW
    fmov    w9, s12
    fmov    w10, s13
    orr     w1, w9, w10, lsl #8
    sub     PTR, PTR, #16
    sub     PTR, PTR, INPUT 
    mov     x0, PTR
    ret
scalar:
    mov     SCALAR_PTR, PTR
    sub     OFFSET, LEN, #1 // -1 for last
    sub     END_INPUT, END_INPUT, OFFSET
    sub     OFFSET, OFFSET, #1 // -1 post increment
    mov     MASK, #1
    mov     RES_SCALAR, #0
scalar_loop:
    cmp     PTR, END_INPUT
    b.eq    end
    ldrb    SCRATCH_W, [PTR], #1
    cmp     SCRATCH_W, FIRST
    b.ne    scalar_next
    ldrb    SCRATCH_W, [PTR, OFFSET]
    cmp     SCRATCH_W, LAST
    b.ne    scalar_next
    orr     RES_SCALAR, RES_SCALAR, MASK
scalar_next:
    lsl     MASK, MASK, #1
    b scalar_loop
end:
    cmp     RES_SCALAR, #0
    b.eq    not_found
    sub     x0, SCALAR_PTR, INPUT
    mov     x1, RES_SCALAR
    ret
not_found:
    mov     x0, #-1
    mov     x1, #0
    ret

.align 8
.bit_weights:
    .byte 1,2,4,8,16,32,64,128,1,2,4,8,16,32,64,128