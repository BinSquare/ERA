// ERA Agent Node.js SDK
// Provides a high-level interface to the ERA Agent API

const fetch = (...args) => import('node-fetch').then(({default: nodeFetch}) => nodeFetch(...args));

class ERAAgent {
  constructor(options = {}) {
    this.baseUrl = options.baseUrl || 'http://localhost:8080';
    this.apiKey = options.apiKey || process.env.ERA_API_KEY || null;
    this.timeout = options.timeout || 30000; // 30 seconds default timeout
  }

  /**
   * Make an HTTP request to the API
   * @param {string} endpoint - API endpoint
   * @param {string} method - HTTP method
   * @param {object} data - Request body data
   * @returns {Promise} - API response
   */
  async _makeRequest(endpoint, method = 'POST', data = null) {
    const url = `${this.baseUrl}${endpoint}`;
    
    const headers = {
      'Content-Type': 'application/json',
    };
    
    if (this.apiKey) {
      headers['Authorization'] = `Bearer ${this.apiKey}`;
    }

    const config = {
      method,
      headers,
    };

    if (data) {
      config.body = JSON.stringify(data);
    }

    // Implement timeout using AbortController
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), this.timeout);
    
    try {
      const response = await fetch(url, { ...config, signal: controller.signal });
      clearTimeout(timeoutId);
      
      const result = await response.json();
      
      if (!response.ok) {
        throw new Error(`API error: ${result.error || `HTTP ${response.status}`}`);
      }
      
      return result.data;
    } catch (error) {
      clearTimeout(timeoutId);
      if (error.name === 'AbortError') {
        throw new Error(`Request timeout after ${this.timeout}ms`);
      }
      throw new Error(`Network or API error: ${error.message}`);
    }
  }

  /**
   * Create a new VM
   * @param {object} options - VM creation options
   * @returns {Promise<object>} - The created VM record
   */
  async createVM(options) {
    const {
      language = 'python',
      image = '',
      cpu = 1,
      mem = 256,
      network = 'none',
      persist = false
    } = options;

    const reqData = {
      language,
      image,
      cpu,
      memory: mem,
      network,
      persist
    };

    try {
      const result = await this._makeRequest('/api/vm/create', 'POST', reqData);
      return result;
    } catch (error) {
      throw new Error(`VM creation failed: ${error.message}`);
    }
  }

  /**
   * Execute a command in a VM
   * @param {string} vmId - The VM ID
   * @param {string} command - The command to execute
   * @param {object} options - Additional options
   * @returns {Promise<object>} - Execution result
   */
  async executeInVM(vmId, command, options = {}) {
    const {
      file = '',
      timeout = 30
    } = options;

    const reqData = {
      vm_id: vmId,
      command,
      file,
      timeout
    };

    try {
      const result = await this._makeRequest('/api/vm/execute', 'POST', reqData);
      return result;
    } catch (error) {
      throw new Error(`Command execution in VM failed: ${error.message}`);
    }
  }

  /**
   * Run a command in an ephemeral/temporary VM
   * @param {string} language - Programming language
   * @param {string} command - The command to execute
   * @param {object} options - Additional options
   * @returns {Promise<object>} - Execution result
   */
  async runTemp(language, command, options = {}) {
    const {
      cpu = 1,
      mem = 256,
      network = 'none',
      timeout = 30,
      file = ''
    } = options;

    const reqData = {
      language,
      command,
      cpu,
      memory: mem,
      network,
      timeout,
      file
    };

    try {
      const result = await this._makeRequest('/api/vm/temp', 'POST', reqData);
      return result;
    } catch (error) {
      throw new Error(`Temporary VM execution failed: ${error.message}`);
    }
  }

  /**
   * List all VMs
   * @param {object} options - List options
   * @returns {Promise<array>} - Array of VM records
   */
  async listVMs(options = {}) {
    const { status = null, all = false } = options;
    
    let url = '/api/vm/list';
    const params = [];
    
    if (status) params.push(`status=${encodeURIComponent(status)}`);
    if (all) params.push('all=true');
    
    if (params.length > 0) {
      url += '?' + params.join('&');
    }

    try {
      const result = await this._makeRequest(url, 'GET');
      return result;
    } catch (error) {
      throw new Error(`VM listing failed: ${error.message}`);
    }
  }

  /**
   * Stop a VM
   * @param {string|Array} vmIds - VM ID or array of VM IDs
   * @returns {Promise} - Resolves when VM is stopped
   */
  async stopVM(vmIds) {
    const reqData = { vm_id: Array.isArray(vmIds) ? vmIds[0] : vmIds }; // For single VM stop
    // For multiple VMs, we'd need to make multiple requests or modify the API
    
    try {
      const result = await this._makeRequest('/api/vm/stop', 'POST', reqData);
      return result;
    } catch (error) {
      throw new Error(`VM stop failed: ${error.message}`);
    }
  }

  /**
   * Clean (remove) a VM
   * @param {string|Array} vmIds - VM ID or array of VM IDs
   * @param {boolean} keepPersist - Whether to keep persistent volumes
   * @returns {Promise} - Resolves when VM is cleaned
   */
  async cleanVM(vmIds, keepPersist = false) {
    const reqData = {
      vm_id: Array.isArray(vmIds) ? vmIds[0] : vmIds, // For single VM clean
      keep_persist: keepPersist
    };
    
    try {
      const result = await this._makeRequest('/api/vm/clean', 'POST', reqData);
      return result;
    } catch (error) {
      throw new Error(`VM cleanup failed: ${error.message}`);
    }
  }

  /**
   * Start an interactive shell in a VM
   * Note: This would require WebSocket connection in practice
   * @param {string} vmId - The VM ID
   * @param {string} shellCommand - The shell command to run
   * @returns {Promise} - Resolves when shell session ends
   */
  async shell(vmId, shellCommand = '/bin/bash') {
    // Shell functionality would typically require WebSocket
    // For now, return a not implemented error
    throw new Error('Shell functionality requires WebSocket connection and is not yet implemented in the API');
  }
}

// Export the ERAAgent class
module.exports = ERAAgent;

// Also export a convenience function to create an instance
module.exports.create = (options) => new ERAAgent(options);