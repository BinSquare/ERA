#ifndef AGENT_VM_LAUNCHER_H
#define AGENT_VM_LAUNCHER_H

#include <stdint.h>

typedef struct AgentVMConfig {
    const char *id;
    const char *rootfs_image;
    uint32_t cpu_count;
    uint32_t memory_mib;
    const char *network_mode;
} AgentVMConfig;

int agent_launch_vm(const AgentVMConfig *config);
int agent_stop_vm(const char *vm_id);
int agent_cleanup_vm(const char *vm_id);

#endif /* AGENT_VM_LAUNCHER_H */
