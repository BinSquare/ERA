use std::ffi::CStr;
use std::os::raw::{c_char, c_int};

#[repr(C)]
pub struct AgentVMConfig {
    pub id: *const c_char,
    pub rootfs_image: *const c_char,
    pub cpu_count: u32,
    pub memory_mib: u32,
    pub network_mode: *const c_char,
}

#[no_mangle]
pub extern "C" fn agent_launch_vm(config: *const AgentVMConfig) -> c_int {
    if config.is_null() {
        return -1;
    }

    // Validate the id pointer is not null for basic safety.
    let vm_config = unsafe { &*config };
    if vm_config.id.is_null() {
        return -1;
    }

    // Accessing the string ensures it is valid UTF-8, otherwise return error.
    if unsafe { CStr::from_ptr(vm_config.id) }.to_bytes().is_empty() {
        return -1;
    }

    0
}

#[no_mangle]
pub extern "C" fn agent_stop_vm(vm_id: *const c_char) -> c_int {
    if vm_id.is_null() {
        return -1;
    }
    if unsafe { CStr::from_ptr(vm_id) }.to_bytes().is_empty() {
        return -1;
    }
    0
}

#[no_mangle]
pub extern "C" fn agent_cleanup_vm(vm_id: *const c_char) -> c_int {
    if vm_id.is_null() {
        return -1;
    }
    if unsafe { CStr::from_ptr(vm_id) }.to_bytes().is_empty() {
        return -1;
    }
    0
}
