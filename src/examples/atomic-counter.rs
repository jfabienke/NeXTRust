//! Parallel counter test for atomic operations
//! Tests our spinlock-based atomic implementation

#![no_std]
#![no_main]
#![feature(core_intrinsics)]

extern crate nextstep_alloc;
extern crate nextstep_atomics;
extern crate nextstep_io;

use nextstep_io::{println, eprintln};
use core::panic::PanicInfo;

// Import atomic operations
extern "C" {
    fn __sync_fetch_and_add_4(ptr: *mut u32, val: u32) -> u32;
    fn __sync_val_compare_and_swap_4(ptr: *mut u32, oldval: u32, newval: u32) -> u32;
    fn __atomic_load_4(src: *const u32, ordering: i32) -> u32;
    fn __atomic_store_4(dst: *mut u32, val: u32, ordering: i32);
}

// Global counter for testing
static mut COUNTER: u32 = 0;

// Sequential consistency ordering
const SEQ_CST: i32 = 5;

#[no_mangle]
pub extern "C" fn main() -> i32 {
    println!("=== NeXTRust Atomic Operations Test ===");
    
    unsafe {
        // Test 1: Basic atomic load/store
        println!("\nTest 1: Atomic Load/Store");
        __atomic_store_4(&mut COUNTER, 42, SEQ_CST);
        let val = __atomic_load_4(&COUNTER, SEQ_CST);
        println!("Stored 42, loaded: {}", val);
        if val != 42 {
            eprintln!("FAIL: Expected 42, got {}", val);
            return 1;
        }
        
        // Test 2: Fetch and add
        println!("\nTest 2: Fetch and Add");
        COUNTER = 0;
        for i in 0..10 {
            let old = __sync_fetch_and_add_4(&mut COUNTER, 1);
            println!("Iteration {}: old={}, new={}", i, old, old + 1);
        }
        let final_val = __atomic_load_4(&COUNTER, SEQ_CST);
        println!("Final counter value: {}", final_val);
        if final_val != 10 {
            eprintln!("FAIL: Expected 10, got {}", final_val);
            return 1;
        }
        
        // Test 3: Compare and swap
        println!("\nTest 3: Compare and Swap");
        COUNTER = 100;
        
        // Successful CAS
        let old = __sync_val_compare_and_swap_4(&mut COUNTER, 100, 200);
        println!("CAS(100->200): old={}, success={}", old, old == 100);
        
        // Failed CAS
        let old = __sync_val_compare_and_swap_4(&mut COUNTER, 100, 300);
        println!("CAS(100->300): old={}, success={}", old, old == 100);
        
        let current = __atomic_load_4(&COUNTER, SEQ_CST);
        println!("Current value: {}", current);
        if current != 200 {
            eprintln!("FAIL: Expected 200, got {}", current);
            return 1;
        }
        
        // Test 4: Simulated concurrent increments
        println!("\nTest 4: Simulated Concurrent Increments");
        COUNTER = 0;
        
        // Simulate multiple "threads" incrementing
        for round in 0..5 {
            println!("Round {}: ", round);
            
            // Each "thread" does 10 increments
            for _thread in 0..3 {
                for _ in 0..10 {
                    __sync_fetch_and_add_4(&mut COUNTER, 1);
                }
            }
            
            let val = __atomic_load_4(&COUNTER, SEQ_CST);
            println!("  Counter after round: {}", val);
        }
        
        let final_count = __atomic_load_4(&COUNTER, SEQ_CST);
        println!("Final count: {}", final_count);
        if final_count != 150 { // 5 rounds * 3 threads * 10 increments
            eprintln!("FAIL: Expected 150, got {}", final_count);
            return 1;
        }
        
        println!("\n✅ All tests passed!");
        println!("TEST_PASS");
    }
    
    0
}

#[panic_handler]
fn panic(info: &PanicInfo) -> ! {
    eprintln!("PANIC: {}", info);
    eprintln!("TEST_FAIL");
    nextstep_sys::sys_exit(1);
}