.section .text
.global _start

_start:
    // Load A0/B0 into RAM buffers (A_BASE=0x240, B_BASE=0x280).
    la   x10, a0_init
    addi x11, x0, 0x240
    jal  x1, copy16

    la   x10, b0_init
    addi x11, x0, 0x280
    jal  x1, copy16

    // First custom matmul.
    addi x1, x0, 0x240
    addi x2, x0, 0x280
    .word 0x5420818b

    // Regular instructions after first custom op.
    lw   x4, 0x200(x0)    // c00 for first run
    sw   x4, 0(x0)        // sentinel #1 expected 0x00000400
    addi x9, x4, 123
    sw   x9, 8(x0)        // marker write proving regular instruction flow

    // Load A1/B1 into RAM buffers.
    la   x10, a1_init
    addi x11, x0, 0x240
    jal  x1, copy16

    la   x10, b1_init
    addi x11, x0, 0x280
    jal  x1, copy16

    // Second custom matmul.
    addi x1, x0, 0x240
    addi x2, x0, 0x280
    .word 0x5420818b

    lw   x5, 0x200(x0)    // c00 for second run
    sw   x5, 4(x0)        // sentinel #2 expected 0xFFFFFC00

1:
    jal  x0, 1b

copy16:
    addi x12, x0, 16
copy16_loop:
    lw   x13, 0(x10)
    sw   x13, 0(x11)
    addi x10, x10, 4
    addi x11, x11, 4
    addi x12, x12, -1
    bne  x12, x0, copy16_loop
    jalr x0, x1, 0

.section .rodata

// First run: A0 = I, B0 = sequence -> c00 = +1.0 (0x00000400)
a0_init:
    .word 0x00000400, 0x00000000, 0x00000000, 0x00000000
    .word 0x00000000, 0x00000400, 0x00000000, 0x00000000
    .word 0x00000000, 0x00000000, 0x00000400, 0x00000000
    .word 0x00000000, 0x00000000, 0x00000000, 0x00000400

b0_init:
    .word 0x00000400, 0x00000800, 0x00000c00, 0x00001000
    .word 0x00001400, 0x00001800, 0x00001c00, 0x00002000
    .word 0x00002400, 0x00002800, 0x00002c00, 0x00003000
    .word 0x00003400, 0x00003800, 0x00003c00, 0x00004000

// Second run: A1 = -I, B1 = sequence -> c00 = -1.0 (0xFFFFFC00)
a1_init:
    .word 0xfffffc00, 0x00000000, 0x00000000, 0x00000000
    .word 0x00000000, 0xfffffc00, 0x00000000, 0x00000000
    .word 0x00000000, 0x00000000, 0xfffffc00, 0x00000000
    .word 0x00000000, 0x00000000, 0x00000000, 0xfffffc00

b1_init:
    .word 0x00000400, 0x00000800, 0x00000c00, 0x00001000
    .word 0x00001400, 0x00001800, 0x00001c00, 0x00002000
    .word 0x00002400, 0x00002800, 0x00002c00, 0x00003000
    .word 0x00003400, 0x00003800, 0x00003c00, 0x00004000
