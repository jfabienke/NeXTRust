// build.rs - Link against NeXTSTEP system libraries

fn main() {
    // Tell cargo to link against libSystem
    println!("cargo:rustc-link-arg=-lSystem");
    
    // Ensure we're using static linking
    println!("cargo:rustc-link-arg=-static");
    
    // Add library search path if needed
    // println!("cargo:rustc-link-search=native=/usr/lib");
}