#ifndef TILED_MATMUL_LIB_H
#define TILED_MATMUL_LIB_H

typedef unsigned int uint32_t;
typedef signed int int32_t;
typedef signed short int16_t;

#ifndef TILE_DIM
#define TILE_DIM 4u
#endif

#ifndef TILE_ELEMS
#define TILE_ELEMS 16u
#endif

#ifndef TILE_A_BASE_WORD_ADDR
#define TILE_A_BASE_WORD_ADDR 0x100u
#endif

#ifndef TILE_B_BASE_WORD_ADDR
#define TILE_B_BASE_WORD_ADDR 0x140u
#endif

#ifndef TILE_C_BASE_WORD_ADDR
#define TILE_C_BASE_WORD_ADDR 0x200u
#endif

#ifndef FULL_A_BASE_WORD_ADDR
#define FULL_A_BASE_WORD_ADDR 0x1000u
#endif

#ifndef FULL_B_BASE_WORD_ADDR
#define FULL_B_BASE_WORD_ADDR 0x2000u
#endif

#ifndef FULL_C_BASE_WORD_ADDR
#define FULL_C_BASE_WORD_ADDR 0x3000u
#endif

#ifndef TILED_START_MARKER_ADDR
#define TILED_START_MARKER_ADDR 0x00000008u
#endif

#ifndef TILED_START_MARKER_VALUE
#define TILED_START_MARKER_VALUE 0x54494C45u
#endif

static inline volatile uint32_t *word_base(uint32_t addr) {
    return (volatile uint32_t *)addr;
}

static inline void write_tiled_start_marker(void) {
    word_base(TILED_START_MARKER_ADDR)[0] = TILED_START_MARKER_VALUE;
}

static inline uint32_t mat_index(uint32_t dim, uint32_t row, uint32_t col) {
    return (row * dim) + col;
}

static inline int16_t load_q5_10(uint32_t base_addr, uint32_t word_index) {
    return (int16_t)word_base(base_addr)[word_index];
}

static inline void store_q5_10(uint32_t base_addr, uint32_t word_index, int32_t value) {
    word_base(base_addr)[word_index] = (uint32_t)(int32_t)(int16_t)value;
}

static inline int32_t q5_10_mul_acc(int32_t acc, int16_t a_val, int16_t b_val) {
    return acc + ((((int32_t)a_val) * ((int32_t)b_val)) >> 10);
}

static inline void zero_region(uint32_t base_addr, uint32_t words) {
    volatile uint32_t *const base = word_base(base_addr);
    uint32_t i;
    for (i = 0; i < words; i++) {
        base[i] = 0u;
    }
}

static inline void copy_inputs_to_full_buffers(uint32_t dim, const uint32_t *a_src, const uint32_t *b_src) {
    volatile uint32_t *const full_a = word_base(FULL_A_BASE_WORD_ADDR);
    volatile uint32_t *const full_b = word_base(FULL_B_BASE_WORD_ADDR);
    uint32_t elems = dim * dim;
    uint32_t i;
    for (i = 0; i < elems; i++) {
        full_a[i] = a_src[i];
        full_b[i] = b_src[i];
    }
    zero_region(FULL_C_BASE_WORD_ADDR, elems);
}

static inline void load_full_tile(uint32_t full_base_addr, uint32_t dim, uint32_t row0, uint32_t col0, int16_t tile[TILE_ELEMS]) {
    uint32_t row;
    uint32_t col;
    for (row = 0; row < TILE_DIM; row++) {
        for (col = 0; col < TILE_DIM; col++) {
            uint32_t tile_idx = (row * TILE_DIM) + col;
            uint32_t src_row = row0 + row;
            uint32_t src_col = col0 + col;
            if (src_row < dim && src_col < dim) {
                tile[tile_idx] = load_q5_10(full_base_addr, mat_index(dim, src_row, src_col));
            } else {
                tile[tile_idx] = 0;
            }
        }
    }
}

static inline void write_staging_tile(uint32_t staging_base_addr, const int16_t tile[TILE_ELEMS]) {
    volatile uint32_t *const staging = word_base(staging_base_addr);
    uint32_t i;
    for (i = 0; i < TILE_ELEMS; i++) {
        staging[i] = (uint32_t)(int32_t)tile[i];
    }
}

static inline void read_staging_tile(uint32_t staging_base_addr, int16_t tile[TILE_ELEMS]) {
    volatile uint32_t *const staging = word_base(staging_base_addr);
    uint32_t i;
    for (i = 0; i < TILE_ELEMS; i++) {
        tile[i] = (int16_t)staging[i];
    }
}

static inline void pcpi_matmul_with_fixed_regs(uint32_t a_base, uint32_t b_base) {
    __asm__ volatile (
        "mv t0, ra\n"
        "mv t1, sp\n"
        "mv t2, gp\n"
        "mv ra, %0\n"
        "mv sp, %1\n"
        ".word 0x5420818b\n"
        "mv gp, t2\n"
        "mv sp, t1\n"
        "mv ra, t0\n"
        :
        : "r"(a_base), "r"(b_base)
        : "ra", "gp", "t0", "t1", "t2", "memory"
    );
}

static inline void accel_kernel_4x4(const int16_t a_tile[TILE_ELEMS], const int16_t b_tile[TILE_ELEMS], int16_t c_tile[TILE_ELEMS]) {
    write_staging_tile(TILE_A_BASE_WORD_ADDR, a_tile);
    write_staging_tile(TILE_B_BASE_WORD_ADDR, b_tile);
    pcpi_matmul_with_fixed_regs(TILE_A_BASE_WORD_ADDR, TILE_B_BASE_WORD_ADDR);
    read_staging_tile(TILE_C_BASE_WORD_ADDR, c_tile);
}

static inline void sw_kernel_4x4(const int16_t a_tile[TILE_ELEMS], const int16_t b_tile[TILE_ELEMS], int16_t c_tile[TILE_ELEMS]) {
    uint32_t row;
    uint32_t col;
    uint32_t dot;
    for (row = 0; row < TILE_DIM; row++) {
        for (col = 0; col < TILE_DIM; col++) {
            int32_t acc = 0;
            for (dot = 0; dot < TILE_DIM; dot++) {
                int16_t a_val = a_tile[(row * TILE_DIM) + dot];
                int16_t b_val = b_tile[(dot * TILE_DIM) + col];
                acc = q5_10_mul_acc(acc, a_val, b_val);
            }
            c_tile[(row * TILE_DIM) + col] = (int16_t)acc;
        }
    }
}

static inline void matmul_accel_tiled_q5_10_square(uint32_t dim) {
    int16_t a_tile[TILE_ELEMS];
    int16_t b_tile[TILE_ELEMS];
    int16_t c_tile[TILE_ELEMS];
    int32_t tile_acc[TILE_ELEMS];
    uint32_t row0;
    uint32_t col0;
    uint32_t k0;
    uint32_t idx;
    uint32_t row;
    uint32_t col;

    for (row0 = 0; row0 < dim; row0 += TILE_DIM) {
        for (col0 = 0; col0 < dim; col0 += TILE_DIM) {
            for (idx = 0; idx < TILE_ELEMS; idx++) {
                tile_acc[idx] = 0;
            }
            for (k0 = 0; k0 < dim; k0 += TILE_DIM) {
                load_full_tile(FULL_A_BASE_WORD_ADDR, dim, row0, k0, a_tile);
                load_full_tile(FULL_B_BASE_WORD_ADDR, dim, k0, col0, b_tile);
                accel_kernel_4x4(a_tile, b_tile, c_tile);
                for (idx = 0; idx < TILE_ELEMS; idx++) {
                    tile_acc[idx] += (int32_t)c_tile[idx];
                }
            }
            for (row = 0; row < TILE_DIM; row++) {
                for (col = 0; col < TILE_DIM; col++) {
                    uint32_t dst_row = row0 + row;
                    uint32_t dst_col = col0 + col;
                    if (dst_row < dim && dst_col < dim) {
                        idx = (row * TILE_DIM) + col;
                        store_q5_10(FULL_C_BASE_WORD_ADDR, mat_index(dim, dst_row, dst_col), tile_acc[idx]);
                    }
                }
            }
        }
    }
}

static inline void matmul_sw_q5_10_square(uint32_t dim) {
    uint32_t row;
    uint32_t col;
    uint32_t dot;
    for (row = 0; row < dim; row++) {
        for (col = 0; col < dim; col++) {
            int32_t acc = 0;
            for (dot = 0; dot < dim; dot++) {
                int16_t a_val = load_q5_10(FULL_A_BASE_WORD_ADDR, mat_index(dim, row, dot));
                int16_t b_val = load_q5_10(FULL_B_BASE_WORD_ADDR, mat_index(dim, dot, col));
                acc = q5_10_mul_acc(acc, a_val, b_val);
            }
            store_q5_10(FULL_C_BASE_WORD_ADDR, mat_index(dim, row, col), acc);
        }
    }
}

#endif
