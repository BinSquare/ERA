// Type definitions for ERA Agent Node.js SDK
declare class ERAAgent {
  constructor(options?: {
    baseUrl?: string;
    apiKey?: string;
    timeout?: number;
  });

  /**
   * Create a new VM
   */
  createVM(options: {
    language?: string;
    image?: string;
    cpu?: number;
    mem?: number;
    network?: string;
    persist?: boolean;
  }): Promise<{
    id: string;
    language: string;
    status: string;
    cpu_count: number;
    memory_mib: number;
    network_mode: string;
    persist: boolean;
    created_at: string;
    last_run_at: string;
  }>;

  /**
   * Execute a command in a VM
   */
  executeInVM(
    vmId: string,
    command: string,
    options?: {
      file?: string;
      timeout?: number;
    }
  ): Promise<{
    vm_id: string;
    exit_code: number;
    stdout: string;
    stderr: string;
    duration: string;
  }>;

  /**
   * Run a command in an ephemeral/temporary VM
   */
  runTemp(
    language: string,
    command: string,
    options?: {
      cpu?: number;
      mem?: number;
      network?: string;
      timeout?: number;
      file?: string;
    }
  ): Promise<{
    exit_code: number;
    stdout: string;
    stderr: string;
    duration: string;
    vm_id: string;
  }>;

  /**
   * List all VMs
   */
  listVMs(options?: {
    status?: string;
    all?: boolean;
  }): Promise<Array<{
    id: string;
    language: string;
    status: string;
    cpu_count: number;
    memory_mib: number;
    network_mode: string;
    persist: boolean;
    created_at: string;
    last_run_at: string;
  }>>;

  /**
   * Stop one or more VMs
   */
  stopVM(vmId: string): Promise<any>;

  /**
   * Clean (remove) one or more VMs
   */
  cleanVM(vmId: string, keepPersist?: boolean): Promise<any>;

  /**
   * Start an interactive shell in a VM
   */
  shell(vmId: string, shellCommand?: string): Promise<any>;
}

export = ERAAgent;

// Factory function
export function create(options?: {
  baseUrl?: string;
  apiKey?: string;
  timeout?: number;
}): ERAAgent;