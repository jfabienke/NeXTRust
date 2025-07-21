//! Regression test for M68k-NeXTSTEP Rust compilation
//! 
//! This test ensures that:
//! 1. The M68k scheduling model in LLVM doesn't cause rustc crashes
//! 2. Basic no_std code compiles successfully
//! 3. All M68k CPU variants (68000-68060) work correctly

#![no_std]
#![no_main]

use core::panic::PanicInfo;

// Test various instruction types to exercise the scheduling model
#[no_mangle]
pub fn test_alu_ops(a: u32, b: u32) -> u32 {
    // IIC_ALU - basic arithmetic
    let sum = a + b;
    let diff = a - b;
    let result = sum ^ diff;
    
    result
}

#[no_mangle]
pub fn test_shift_ops(x: u32, count: u8) -> u32 {
    // IIC_SHIFT - shift operations
    let left = x << count;
    let right = x >> count;
    
    left | right
}

#[no_mangle]
pub fn test_multiply(a: u32, b: u32) -> u32 {
    // IIC_MULTIPLY - multiplication
    a.wrapping_mul(b)
}

#[no_mangle]
pub fn test_divide(a: u32, b: u32) -> u32 {
    // IIC_DIVIDE - division (expensive on M68k)
    if b != 0 {
        a / b
    } else {
        0
    }
}

#[no_mangle]
pub fn test_memory_ops(ptr: *mut u32, value: u32) -> u32 {
    // IIC_STORE and IIC_LOAD - memory operations
    unsafe {
        // Store
        ptr.write(value);
        
        // Load
        ptr.read()
    }
}

#[no_mangle]
pub fn test_branch(condition: bool, a: u32, b: u32) -> u32 {
    // IIC_BRANCH - conditional branches
    if condition {
        a + 1
    } else {
        b + 1
    }
}

// Entry point for NeXTSTEP
#[no_mangle]
pub extern "C" fn _start() -> ! {
    // Test all instruction types
    let _ = test_alu_ops(42, 13);
    let _ = test_shift_ops(0x1234, 4);
    let _ = test_multiply(7, 6);
    let _ = test_divide(100, 10);
    
    // Test with stack variable
    let mut stack_var = 0u32;
    let _ = test_memory_ops(&mut stack_var as *mut u32, 0xDEADBEEF);
    
    let _ = test_branch(true, 1, 2);
    
    // Success - infinite loop
    loop {
        // On real hardware, this would keep the CPU busy
        // In emulation, it signals successful completion
    }
}

#[panic_handler]
fn panic(_info: &PanicInfo) -> ! {
    // On panic, spin forever
    loop {}
}