//! atomic_smoke.rs - Basic atomic operations test for m68k-next-nextstep
//! Tests that our spin-lock based atomics work correctly

#![no_std]
#![no_main]

use core::sync::atomic::{AtomicU32, AtomicU8, Ordering};
use core::panic::PanicInfo;

#[panic_handler]
fn panic(_info: &PanicInfo) -> ! {
    // Write error to console using nextstep-sys
    extern "C" {
        fn write(fd: i32, buf: *const u8, count: usize) -> isize;
        fn _exit(status: i32) -> !;
    }
    
    let msg = b"PANIC\n";
    unsafe {
        write(2, msg.as_ptr(), msg.len());
        _exit(1);
    }
}

#[no_mangle]
pub extern "C" fn main() -> i32 {
    // Test AtomicU8
    let atomic8 = AtomicU8::new(0);
    atomic8.store(42, Ordering::SeqCst);
    let val8 = atomic8.load(Ordering::SeqCst);
    assert_eq!(val8, 42);
    
    // Test fetch_add
    let old8 = atomic8.fetch_add(10, Ordering::SeqCst);
    assert_eq!(old8, 42);
    assert_eq!(atomic8.load(Ordering::SeqCst), 52);
    
    // Test AtomicU32
    let atomic32 = AtomicU32::new(100);
    let val32 = atomic32.load(Ordering::SeqCst);
    assert_eq!(val32, 100);
    
    // Test compare_exchange
    let result = atomic32.compare_exchange(100, 200, Ordering::SeqCst, Ordering::SeqCst);
    assert!(result.is_ok());
    assert_eq!(atomic32.load(Ordering::SeqCst), 200);
    
    // Test fetch_sub
    let old32 = atomic32.fetch_sub(50, Ordering::SeqCst);
    assert_eq!(old32, 200);
    assert_eq!(atomic32.load(Ordering::SeqCst), 150);
    
    // Test swap
    let old_swap = atomic32.swap(999, Ordering::SeqCst);
    assert_eq!(old_swap, 150);
    assert_eq!(atomic32.load(Ordering::SeqCst), 999);
    
    // Success - write OK message
    extern "C" {
        fn write(fd: i32, buf: *const u8, count: usize) -> isize;
    }
    
    let msg = b"OK: All atomic tests passed\n";
    unsafe {
        write(1, msg.as_ptr(), msg.len());
    }
    
    0 // Success
}

// Simple assert_eq macro
macro_rules! assert_eq {
    ($left:expr, $right:expr) => {
        if !($left == $right) {
            panic!();
        }
    };
}

// Simple assert macro
macro_rules! assert {
    ($cond:expr) => {
        if !($cond) {
            panic!();
        }
    };
}