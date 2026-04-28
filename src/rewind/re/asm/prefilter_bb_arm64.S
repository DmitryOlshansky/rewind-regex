#define INPUT x0
#define END_INPUT x1
#define FIRST w2
#define LAST w3
#define LEN x4
#define OFFSET x5
#define PTR x6
#define V_INPUT_END x7
#define SCRATCH x8

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

.global rewindRePrefilterBB
rewindRePrefilterBB:
    adrp    SCRATCH, .bit_weights
    add     SCRATCH, SCRATCH, :lo12:.bit_weights
    ld1     {BITS_TABLE}, [SCRATCH]
    mov     PTR, INPUT
    sub     V_INPUT_END, END_INPUT, LEN
    movn    SCRATCH, #15
    and     V_INPUT_END, V_INPUT_END, SCRATCH
    mov     OFFSET, LEN
    sub     OFFSET, OFFSET, #15  // offset is relative to (addr+16) postincremented: len - 16
    dup     FIRST_V, FIRST
    dup     LAST_V, LAST
loop_vector:
    cmp     PTR, V_INPUT_END
    b.eq    scalar
    ld1     {BYTES}, [PTR], #16
    cmeq    RES, BYTES, FIRST_V
    umaxv   s11, RES_W
    fmov    w11, s11
    cbz     w11, loop_vector
    
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
    sub PTR, PTR, #16
    mov x0, #-1
    ret

.align 8
.bit_weights:
    .byte 1,2,4,8,16,32,64,128,1,2,4,8,16,32,64,128