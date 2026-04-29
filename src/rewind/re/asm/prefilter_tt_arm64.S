#define INPUT x0
#define END_INPUT x1
#define LENGTH x2
#define FIRST x3
#define LAST x4
#define PTR x5
#define SCRATCH x6

#define FIRST_TABLE v0.16b
#define FIRST_TABLE_2 v1.16b
#define LAST_TABLE v2.16b
#define LAST_TABLE_2 v3.16b
#define MASK_3BIT v4.16b
#define DATA v5.16b
#define BLOCKS v6.16b
#define BMASKS v7.16b
#define LOW v8.16b
#define RES v9.16b
#define RES_D v9.4s
#define ONES v10.16b
#define BITS_TABLE v11.16b

.global rewindRePrefilterTT
rewindRePrefilterTT:
    adrp    SCRATCH, .bit_weights
    add     SCRATCH, SCRATCH, :lo12:.bit_weights
    ld1     {BITS_TABLE}, [SCRATCH]
    mov     PTR, INPUT
    ld1     {FIRST_TABLE, FIRST_TABLE_2}, [FIRST]
    ld1     {LAST_TABLE, LAST_TABLE_2}, [LAST]
    movi    MASK_3BIT, #0x07
    movi    ONES, #1
loop:
    cmp PTR, END_INPUT
    b.eq not_found
    ld1 {DATA}, [PTR], #16
    ushr BLOCKS, DATA, #3
    tbl BMASKS, {FIRST_TABLE}, BLOCKS
    and LOW, DATA, MASK_3BIT
    ushl RES, ONES, LOW
    and RES, RES, BMASKS
    umaxv s11, RES_D
    fmov  w11, s11
    cbz  w11, loop
found:
    sub PTR, PTR, #16
    sub x0, PTR, INPUT
    ret
not_found:
    mov x0, #-1
    ret

.align 8
.bit_weights:
    .byte 1,2,4,8,16,32,64,128,1,2,4,8,16,32,64,128