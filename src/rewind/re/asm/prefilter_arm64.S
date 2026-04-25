.global _rewindRePrefilter
#define INPUT x0
#define END_INPUT x1
#define LENGTH x2
#define FIRST x3
#define LAST x4
#define PTR x5
#define FIRST_TABLE v0.16b
#define LAST_TABLE v1.16b
#define MASK_3BIT v2.16b
#define DATA v3.16b
#define BLOCKS v4.16b
#define BMASKS v5.16b
#define LOW v6.16b
#define RES v7.16b
#define RES_D v7.4s
#define ONES v8.16b

_rewindRePrefilter:
    mov PTR, INPUT
    ld1 {FIRST_TABLE}, [FIRST]
    ld1 {LAST_TABLE}, [LAST]
    movi MASK_3BIT, #0x07
    movi ONES, #1
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

#undef INPUT
#under END_INPUT
#define INPUT x0
#define END_INPUT x1
#define BYTE w2
#undef PTR
#define PTR x3

.global _rewindReFindByte
_rewindReFindByte:
    mov PTR, INPUT
    dup v1.16b, BYTE
loop_byte:
    cmp PTR, END_INPUT
    b.eq not_found_byte
    ld1 {v0.16b}, [PTR], #16
    cmeq v2.16b, v0.16b, v1.16b 
    umaxv s11, v2.4s
    fmov  w11, s11
    cbz  w11, loop_byte
    sub PTR, PTR, #16
    sub x0, PTR, INPUT
    ret
not_found_byte:
    mov x0, #-1
    ret