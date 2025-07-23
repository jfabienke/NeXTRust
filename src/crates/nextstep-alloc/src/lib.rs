//! nextstep-alloc - GlobalAlloc implementation for NeXTSTEP
//! 
//! Provides a memory allocator using Mach VM syscalls

#![no_std]
#![feature(allocator_api)]

use core::alloc::{GlobalAlloc, Layout};
use core::ptr;
use nextstep_sys::{sys_vm_allocate, sys_vm_deallocate, VM_PROT_READ, VM_PROT_WRITE};

/// Simple allocator using Mach VM syscalls
/// 
/// This allocator is very basic:
/// - Always allocates full pages (4KB minimum)
/// - No reuse of freed memory
/// - Thread-unsafe (single-threaded only)
pub struct MachAllocator;

// Page size on NeXTSTEP m68k
const PAGE_SIZE: usize = 4096;

fn round_up_to_page(size: usize) -> usize {
    (size + PAGE_SIZE - 1) & !(PAGE_SIZE - 1)
}

unsafe impl GlobalAlloc for MachAllocator {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        // Round up to page size
        let size = round_up_to_page(layout.size());
        
        // Allocate anywhere
        match sys_vm_allocate(size, true) {
            Ok(ptr) => ptr as *mut u8,
            Err(_) => ptr::null_mut(),
        }
    }

    unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
        let size = round_up_to_page(layout.size());
        let _ = sys_vm_deallocate(ptr as *mut core::ffi::c_void, size);
    }
    
    unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
        // vm_allocate already returns zeroed memory
        self.alloc(layout)
    }
}

/// Global allocator instance
#[global_allocator]
pub static ALLOCATOR: MachAllocator = MachAllocator;

/// Allocation error handler required by Rust
#[alloc_error_handler]
fn alloc_error(layout: Layout) -> ! {
    // Write error message and exit
    let msg = b"memory allocation failed\n";
    let _ = nextstep_sys::sys_write(2, msg); // stderr
    nextstep_sys::sys_exit(1);
}

#[cfg(test)]
mod tests {
    use super::*;
    use core::alloc::Layout;
    
    #[test]
    fn test_basic_alloc() {
        unsafe {
            let layout = Layout::from_size_align(64, 8).unwrap();
            let ptr = ALLOCATOR.alloc(layout);
            assert!(!ptr.is_null());
            
            // Write some data
            ptr.write(42);
            assert_eq!(*ptr, 42);
            
            ALLOCATOR.dealloc(ptr, layout);
        }
    }
    
    #[test] 
    fn test_large_alloc() {
        unsafe {
            let layout = Layout::from_size_align(16384, 8).unwrap();
            let ptr = ALLOCATOR.alloc(layout);
            assert!(!ptr.is_null());
            
            ALLOCATOR.dealloc(ptr, layout);
        }
    }
}