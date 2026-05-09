#define INPUT x0
#define END_INPUT x1
#define FIRST x2
#define LAST x3
#define LEN x4
#define PTR x5
#define SCRATCH x6
#define SCRATCH_W w6
#define V_INPUT_END x7
#define OFFSET x8
#define RES_SCALAR x9
#define SCALAR_PTR x10
#define SCRATCH_2 x11
#define SCRATCH_2_W w11
#define SCALAR_LOW x12
#define SCALAR_LOW_W w12
#define SCALAR_DATA x13
#define SCALAR_DATA_W w13
#define MASK x14

#define FIRST_TABLE v0.16b
#define FIRST_TABLE_2 v1.16b
#define LAST_TABLE v2.16b
#define LAST_TABLE_2 v3.16b
#define MASK_3BIT v4.16b
#define DATA v5.16b
#define DATA_Q q5
#define BLOCKS v6.16b
#define BMASKS v16.16b
#define LOW v17.16b
#define RES v18.16b
#define RES_D v18.4s
#define RES_LOW v18.8b
#define RES2 v19.16b
#define ONES v20.16b
#define BITS_TABLE v21.16b

#ifdef __APPLE__
.global _rewindRePrefilterTT
_rewindRePrefilterTT:
    adrp    SCRATCH, .bit_weights@GOTPAGE
    ldr     SCRATCH, [SCRATCH, .bit_weights@GOTPAGEOFF]
 #else
.global rewindRePrefilterTT
rewindRePrefilterTT:
    adrp    SCRATCH, .bit_weights
    add     SCRATCH, SCRATCH, :lo12:.bit_weights
 #endif   
    ld1     {BITS_TABLE}, [SCRATCH]
    mov     PTR, INPUT
    ld1     {FIRST_TABLE, FIRST_TABLE_2}, [FIRST]
    ld1     {LAST_TABLE, LAST_TABLE_2}, [LAST]
    movi    MASK_3BIT, #0x07
    movi    ONES, #1
    sub     V_INPUT_END, END_INPUT, LEN
    movn    SCRATCH, #15
    and     V_INPUT_END, V_INPUT_END, SCRATCH
    sub     OFFSET, LEN, #17  // offset is relative to (addr+16) postincremented: len - 16
loop:
    cmp     PTR, V_INPUT_END
    b.eq    scalar
    ld1     {DATA}, [PTR], #16
    ushr    BLOCKS, DATA, #3
    tbl     BMASKS, {FIRST_TABLE, FIRST_TABLE_2}, BLOCKS
    and     LOW, DATA, MASK_3BIT
    ushl    RES, ONES, LOW
    and     RES, RES, BMASKS
    cmtst   RES, RES, RES
     
    ldr     DATA_Q, [PTR, OFFSET]
    ushr    BLOCKS, DATA, #3
    tbl     BMASKS, {LAST_TABLE, LAST_TABLE_2}, BLOCKS
    and     LOW, DATA, MASK_3BIT
    ushl    RES2, ONES, LOW
    and     RES2, RES2, BMASKS
    cmtst   RES2, RES2, RES2

    and     RES, RES, RES2

    umaxv   s13, RES_D
    fmov    w10, s13
    cbz     w10, loop
    
    and     RES, RES, BITS_TABLE
    uaddlv  h13, RES_LOW
    ext     RES, RES, RES, #8
    uaddlv  h14, RES_LOW
    fmov    w9, s13
    fmov    w10, s14
    orr     w1, w9, w10, lsl #8
    sub     PTR, PTR, #16
    sub     x0, PTR, INPUT 
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
    ldrb    SCALAR_DATA_W, [PTR], #1
    and     SCALAR_LOW_W, SCALAR_DATA_W, #7
    lsr     SCALAR_DATA_W, SCALAR_DATA_W, #3
    ldrb    SCRATCH_W, [FIRST, SCALAR_DATA]
    mov     SCRATCH_2_W, #1
    lsl     SCRATCH_2_W, SCRATCH_2_W, SCALAR_LOW_W
    and     SCRATCH_2_W, SCRATCH_2_W, SCRATCH_W   
    cbz     SCRATCH_2_W, scalar_next

    ldrb    SCALAR_DATA_W, [PTR, OFFSET]
    and     SCALAR_LOW_W, SCALAR_DATA_W, #7
    lsr     SCALAR_DATA_W, SCALAR_DATA_W, #3
    ldrb    SCRATCH_W, [LAST, SCALAR_DATA]
    mov     SCRATCH_2_W, #1
    lsl     SCRATCH_2_W, SCRATCH_2_W, SCALAR_LOW_W
    and     SCRATCH_2_W, SCRATCH_2_W, SCRATCH_W
    cbz     SCRATCH_2_W, scalar_next

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