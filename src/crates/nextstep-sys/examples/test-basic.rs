//! Basic test of nextstep-sys bindings
//! This example just exercises the type definitions to ensure they compile

#![no_std]
#![no_main]

use nextstep_sys::*;

#[no_mangle]
pub extern "C" fn main() -> i32 {
    // Test that constants are accessible
    let _fd = STDOUT_FILENO;
    let _flag = O_RDWR;
    let _err = ENOENT;
    let _sig = SIGINT;
    
    // Test that types work
    let _pid: pid_t = 1;
    let _size: size_t = 42;
    let _mode: mode_t = S_IRUSR | S_IWUSR;
    
    // Test safe wrapper
    let msg = b"Hello from nextstep-sys!\n";
    let _ = sys_write(STDOUT_FILENO, msg);
    
    0
}

#[panic_handler]
fn panic(_info: &core::panic::PanicInfo) -> ! {
    sys_exit(1);
}