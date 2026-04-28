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

.global rewindRePrefilterTT
rewindRePrefilterTT:
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
