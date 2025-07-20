//! hello.rs - Simple hello world for m68k-next-nextstep
//! Demonstrates basic output using nextstep-sys

#![no_std]
#![no_main]

extern crate nextstep_sys;

use core::panic::PanicInfo;
use nextstep_sys::{sys_write, sys_exit, STDOUT_FILENO, STDERR_FILENO};

#[panic_handler]
fn panic(_info: &PanicInfo) -> ! {
    // Write error message and exit
    let msg = b"PANIC\n";
    let _ = sys_write(STDERR_FILENO, msg);
    sys_exit(1);
}

#[no_mangle]
pub extern "C" fn main() -> i32 {
    // Write "OK\n" to stdout
    let msg = b"OK\n";
    match sys_write(STDOUT_FILENO, msg) {
        Ok(_) => 0,  // Success
        Err(_) => 1, // Error
    }
}

// Entry point for no_std
#[no_mangle]
pub extern "C" fn _start() -> ! {
    let exit_code = main();
    sys_exit(exit_code);
}