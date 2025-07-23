//! nextstep-atomics - Atomic operations for M68k without native CAS
//! 
//! Provides software-based atomic operations using spinlocks for
//! processors that lack Compare-And-Swap instructions.

#![no_std]
#![feature(core_intrinsics)]
#![feature(asm_experimental_arch)]

use core::intrinsics;
use core::sync::atomic::Ordering;

// Number of spinlocks (must be power of 2)
const SPINLOCK_COUNT: usize = 64;
const SPINLOCK_MASK: usize = SPINLOCK_COUNT - 1;

// Cache line size for padding (M68k typically 16 bytes)
const CACHE_LINE_SIZE: usize = 16;

#[repr(C, align(16))]
struct PaddedSpinlock {
    locked: u8,
    _padding: [u8; CACHE_LINE_SIZE - 1],
}

// Global spinlock array
static mut SPINLOCKS: [PaddedSpinlock; SPINLOCK_COUNT] = [PaddedSpinlock {
    locked: 0,
    _padding: [0; CACHE_LINE_SIZE - 1],
}; SPINLOCK_COUNT];

// Hash function to map addresses to spinlock indices
#[inline(always)]
fn addr_to_lock_idx(addr: usize) -> usize {
    // Simple hash: use middle bits of address
    (addr >> 4) & SPINLOCK_MASK
}

// Acquire spinlock (busy wait)
#[inline(never)]
unsafe fn acquire_spinlock(lock: &mut PaddedSpinlock) {
    // For single-core M68k, we can use interrupt masking
    // For now, use a simple spinlock
    while lock.locked != 0 {
        // Busy wait - in real implementation would use pause/yield
        core::hint::spin_loop();
    }
    lock.locked = 1;
    
    // Memory barrier
    core::sync::atomic::fence(Ordering::Acquire);
}

// Release spinlock
#[inline(never)]
unsafe fn release_spinlock(lock: &mut PaddedSpinlock) {
    // Memory barrier
    core::sync::atomic::fence(Ordering::Release);
    
    lock.locked = 0;
}

// Atomic load implementation
#[no_mangle]
pub unsafe extern "C" fn __atomic_load_1(src: *const u8, _ordering: i32) -> u8 {
    let idx = addr_to_lock_idx(src as usize);
    let lock = &mut SPINLOCKS[idx];
    
    acquire_spinlock(lock);
    let val = *src;
    release_spinlock(lock);
    
    val
}

#[no_mangle]
pub unsafe extern "C" fn __atomic_load_2(src: *const u16, _ordering: i32) -> u16 {
    let idx = addr_to_lock_idx(src as usize);
    let lock = &mut SPINLOCKS[idx];
    
    acquire_spinlock(lock);
    let val = *src;
    release_spinlock(lock);
    
    val
}

#[no_mangle]
pub unsafe extern "C" fn __atomic_load_4(src: *const u32, _ordering: i32) -> u32 {
    let idx = addr_to_lock_idx(src as usize);
    let lock = &mut SPINLOCKS[idx];
    
    acquire_spinlock(lock);
    let val = *src;
    release_spinlock(lock);
    
    val
}

// Atomic store implementation
#[no_mangle]
pub unsafe extern "C" fn __atomic_store_1(dst: *mut u8, val: u8, _ordering: i32) {
    let idx = addr_to_lock_idx(dst as usize);
    let lock = &mut SPINLOCKS[idx];
    
    acquire_spinlock(lock);
    *dst = val;
    release_spinlock(lock);
}

#[no_mangle]
pub unsafe extern "C" fn __atomic_store_2(dst: *mut u16, val: u16, _ordering: i32) {
    let idx = addr_to_lock_idx(dst as usize);
    let lock = &mut SPINLOCKS[idx];
    
    acquire_spinlock(lock);
    *dst = val;
    release_spinlock(lock);
}

#[no_mangle]
pub unsafe extern "C" fn __atomic_store_4(dst: *mut u32, val: u32, _ordering: i32) {
    let idx = addr_to_lock_idx(dst as usize);
    let lock = &mut SPINLOCKS[idx];
    
    acquire_spinlock(lock);
    *dst = val;
    release_spinlock(lock);
}

// Compare and swap implementation
#[no_mangle]
pub unsafe extern "C" fn __sync_val_compare_and_swap_1(
    ptr: *mut u8,
    oldval: u8,
    newval: u8,
) -> u8 {
    let idx = addr_to_lock_idx(ptr as usize);
    let lock = &mut SPINLOCKS[idx];
    
    acquire_spinlock(lock);
    let current = *ptr;
    if current == oldval {
        *ptr = newval;
    }
    release_spinlock(lock);
    
    current
}

#[no_mangle]
pub unsafe extern "C" fn __sync_val_compare_and_swap_2(
    ptr: *mut u16,
    oldval: u16,
    newval: u16,
) -> u16 {
    let idx = addr_to_lock_idx(ptr as usize);
    let lock = &mut SPINLOCKS[idx];
    
    acquire_spinlock(lock);
    let current = *ptr;
    if current == oldval {
        *ptr = newval;
    }
    release_spinlock(lock);
    
    current
}

#[no_mangle]
pub unsafe extern "C" fn __sync_val_compare_and_swap_4(
    ptr: *mut u32,
    oldval: u32,
    newval: u32,
) -> u32 {
    let idx = addr_to_lock_idx(ptr as usize);
    let lock = &mut SPINLOCKS[idx];
    
    acquire_spinlock(lock);
    let current = *ptr;
    if current == oldval {
        *ptr = newval;
    }
    release_spinlock(lock);
    
    current
}

// Atomic exchange (swap)
#[no_mangle]
pub unsafe extern "C" fn __atomic_exchange_1(
    ptr: *mut u8,
    val: u8,
    _ordering: i32,
) -> u8 {
    let idx = addr_to_lock_idx(ptr as usize);
    let lock = &mut SPINLOCKS[idx];
    
    acquire_spinlock(lock);
    let old = *ptr;
    *ptr = val;
    release_spinlock(lock);
    
    old
}

#[no_mangle]
pub unsafe extern "C" fn __atomic_exchange_2(
    ptr: *mut u16,
    val: u16,
    _ordering: i32,
) -> u16 {
    let idx = addr_to_lock_idx(ptr as usize);
    let lock = &mut SPINLOCKS[idx];
    
    acquire_spinlock(lock);
    let old = *ptr;
    *ptr = val;
    release_spinlock(lock);
    
    old
}

#[no_mangle]
pub unsafe extern "C" fn __atomic_exchange_4(
    ptr: *mut u32,
    val: u32,
    _ordering: i32,
) -> u32 {
    let idx = addr_to_lock_idx(ptr as usize);
    let lock = &mut SPINLOCKS[idx];
    
    acquire_spinlock(lock);
    let old = *ptr;
    *ptr = val;
    release_spinlock(lock);
    
    old
}

// Atomic fetch and add
#[no_mangle]
pub unsafe extern "C" fn __sync_fetch_and_add_1(ptr: *mut u8, val: u8) -> u8 {
    let idx = addr_to_lock_idx(ptr as usize);
    let lock = &mut SPINLOCKS[idx];
    
    acquire_spinlock(lock);
    let old = *ptr;
    *ptr = old.wrapping_add(val);
    release_spinlock(lock);
    
    old
}

#[no_mangle]
pub unsafe extern "C" fn __sync_fetch_and_add_2(ptr: *mut u16, val: u16) -> u16 {
    let idx = addr_to_lock_idx(ptr as usize);
    let lock = &mut SPINLOCKS[idx];
    
    acquire_spinlock(lock);
    let old = *ptr;
    *ptr = old.wrapping_add(val);
    release_spinlock(lock);
    
    old
}

#[no_mangle]
pub unsafe extern "C" fn __sync_fetch_and_add_4(ptr: *mut u32, val: u32) -> u32 {
    let idx = addr_to_lock_idx(ptr as usize);
    let lock = &mut SPINLOCKS[idx];
    
    acquire_spinlock(lock);
    let old = *ptr;
    *ptr = old.wrapping_add(val);
    release_spinlock(lock);
    
    old
}

// Boolean compare and swap
#[no_mangle]
pub unsafe extern "C" fn __sync_bool_compare_and_swap_1(
    ptr: *mut u8,
    oldval: u8,
    newval: u8,
) -> bool {
    __sync_val_compare_and_swap_1(ptr, oldval, newval) == oldval
}

#[no_mangle]
pub unsafe extern "C" fn __sync_bool_compare_and_swap_2(
    ptr: *mut u16,
    oldval: u16,
    newval: u16,
) -> bool {
    __sync_val_compare_and_swap_2(ptr, oldval, newval) == oldval
}

#[no_mangle]
pub unsafe extern "C" fn __sync_bool_compare_and_swap_4(
    ptr: *mut u32,
    oldval: u32,
    newval: u32,
) -> bool {
    __sync_val_compare_and_swap_4(ptr, oldval, newval) == oldval
}

// Memory barrier
#[no_mangle]
pub unsafe extern "C" fn __sync_synchronize() {
    core::sync::atomic::fence(Ordering::SeqCst);
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_atomic_load_store() {
        unsafe {
            let mut val: u32 = 0;
            __atomic_store_4(&mut val, 42, 0);
            assert_eq!(__atomic_load_4(&val, 0), 42);
        }
    }
    
    #[test]
    fn test_compare_and_swap() {
        unsafe {
            let mut val: u32 = 10;
            let old = __sync_val_compare_and_swap_4(&mut val, 10, 20);
            assert_eq!(old, 10);
            assert_eq!(val, 20);
            
            let old = __sync_val_compare_and_swap_4(&mut val, 10, 30);
            assert_eq!(old, 20);
            assert_eq!(val, 20); // No change
        }
    }
    
    #[test]
    fn test_fetch_and_add() {
        unsafe {
            let mut counter: u32 = 0;
            assert_eq!(__sync_fetch_and_add_4(&mut counter, 1), 0);
            assert_eq!(__sync_fetch_and_add_4(&mut counter, 1), 1);
            assert_eq!(__sync_fetch_and_add_4(&mut counter, 1), 2);
            assert_eq!(counter, 3);
        }
    }
}