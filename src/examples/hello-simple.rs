#![no_std]
#![no_main]

// Simple no_std example that avoids compiler_builtins
// This demonstrates that our LLVM patches work for basic code generation

#[no_mangle]
pub extern "C" fn _start() -> ! {
    // Direct assembly to avoid any runtime dependencies
    unsafe {
        // Write "OK\n" to stdout using NeXT syscalls
        core::arch::asm!(
            "move.l #4, d0",      // write syscall
            "move.l #1, d1",      // stdout
            "lea message, a0",    // message address
            "move.l a0, d2",      // buffer
            "move.l #3, d3",      // length
            "trap #0",            // syscall
            
            // Exit
            "move.l #1, d0",      // exit syscall
            "move.l #0, d1",      // status code
            "trap #0",            // syscall
            
            "message:",
            ".ascii \"OK\\n\"",
            options(noreturn)
        );
    }
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    // Simple panic handler - just loop forever
    loop {}
}