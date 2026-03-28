#include "tiled_matmul_lib.h"
#include "tiled_case_data.h"

#ifndef MATMUL_MODE_ACCEL
#define MATMUL_MODE_ACCEL 1
#endif

#ifndef MATMUL_MODE_SW
#define MATMUL_MODE_SW 0
#endif

#if ((MATMUL_MODE_ACCEL + MATMUL_MODE_SW) != 1)
#error "Exactly one mode must be enabled: MATMUL_MODE_ACCEL or MATMUL_MODE_SW."
#endif

static void run_program(void) {
    uint32_t c00;

    copy_inputs_to_full_buffers(TILED_CASE_DIM, a_init, b_init);
    write_tiled_start_marker();

#if MATMUL_MODE_ACCEL
    matmul_accel_tiled_q5_10_square(TILED_CASE_DIM);
#endif

#if MATMUL_MODE_SW
    matmul_sw_q5_10_square(TILED_CASE_DIM);
#endif

    c00 = word_base(FULL_C_BASE_WORD_ADDR)[0];
    __asm__ volatile ("sw %0, 0(x0)" :: "r"(c00) : "memory");
}

void _start(void) __attribute__((noreturn));
void _start(void) {
    run_program();
    while (1) {
        __asm__ volatile ("jal x0, .");
    }
}
