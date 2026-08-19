#include <stdint.h>

/*
 * Kotlin/Native 2.4.10's ARM32 runtime still references these legacy GCC
 * synchronization helpers. NDK r29's compiler-rt does not provide them.
 *
 * C identifiers are deliberately different from the exported assembler names
 * so Clang does not rewrite the function declarations as __sync builtins.
 */

void konan_sync_synchronize(void) __asm__("__sync_synchronize");
void konan_sync_synchronize(void) {
    __atomic_thread_fence(__ATOMIC_SEQ_CST);
}

uint8_t konan_sync_val_compare_and_swap_1(
    volatile uint8_t *pointer,
    uint8_t old_value,
    uint8_t new_value
) __asm__("__sync_val_compare_and_swap_1");
uint8_t konan_sync_val_compare_and_swap_1(
    volatile uint8_t *pointer,
    uint8_t old_value,
    uint8_t new_value
) {
    uint8_t expected = old_value;
    __atomic_compare_exchange_n(
        pointer,
        &expected,
        new_value,
        0,
        __ATOMIC_SEQ_CST,
        __ATOMIC_SEQ_CST
    );
    return expected;
}

uint32_t konan_sync_val_compare_and_swap_4(
    volatile uint32_t *pointer,
    uint32_t old_value,
    uint32_t new_value
) __asm__("__sync_val_compare_and_swap_4");
uint32_t konan_sync_val_compare_and_swap_4(
    volatile uint32_t *pointer,
    uint32_t old_value,
    uint32_t new_value
) {
    uint32_t expected = old_value;
    __atomic_compare_exchange_n(
        pointer,
        &expected,
        new_value,
        0,
        __ATOMIC_SEQ_CST,
        __ATOMIC_SEQ_CST
    );
    return expected;
}

uint64_t konan_sync_val_compare_and_swap_8(
    volatile uint64_t *pointer,
    uint64_t old_value,
    uint64_t new_value
) __asm__("__sync_val_compare_and_swap_8");
uint64_t konan_sync_val_compare_and_swap_8(
    volatile uint64_t *pointer,
    uint64_t old_value,
    uint64_t new_value
) {
    uint64_t expected = old_value;
    __atomic_compare_exchange_n(
        pointer,
        &expected,
        new_value,
        0,
        __ATOMIC_SEQ_CST,
        __ATOMIC_SEQ_CST
    );
    return expected;
}

uint8_t konan_sync_lock_test_and_set_1(
    volatile uint8_t *pointer,
    uint8_t value
) __asm__("__sync_lock_test_and_set_1");
uint8_t konan_sync_lock_test_and_set_1(
    volatile uint8_t *pointer,
    uint8_t value
) {
    return __atomic_exchange_n(pointer, value, __ATOMIC_SEQ_CST);
}

uint32_t konan_sync_lock_test_and_set_4(
    volatile uint32_t *pointer,
    uint32_t value
) __asm__("__sync_lock_test_and_set_4");
uint32_t konan_sync_lock_test_and_set_4(
    volatile uint32_t *pointer,
    uint32_t value
) {
    return __atomic_exchange_n(pointer, value, __ATOMIC_SEQ_CST);
}

uint64_t konan_sync_lock_test_and_set_8(
    volatile uint64_t *pointer,
    uint64_t value
) __asm__("__sync_lock_test_and_set_8");
uint64_t konan_sync_lock_test_and_set_8(
    volatile uint64_t *pointer,
    uint64_t value
) {
    return __atomic_exchange_n(pointer, value, __ATOMIC_SEQ_CST);
}

uint16_t konan_sync_fetch_and_or_2(
    volatile uint16_t *pointer,
    uint16_t value
) __asm__("__sync_fetch_and_or_2");
uint16_t konan_sync_fetch_and_or_2(
    volatile uint16_t *pointer,
    uint16_t value
) {
    return __atomic_fetch_or(pointer, value, __ATOMIC_SEQ_CST);
}
