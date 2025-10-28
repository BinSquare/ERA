// Example 2: VM lifecycle management
const ERAAgent = require('../index.js');

async function vmLifecycleExample() {
  console.log('=== VM Lifecycle Example ===');
  
  const agent = new ERAAgent({
    agentPath: '../../../agent', // Adjust path based on your setup
    env: process.env
  });

  let vmId;
  
  try {
    // Create a Python VM
    console.log('Creating Python VM...');
    const vm = await agent.createVM({
      language: 'python',
      cpu: 1,
      mem: 256,
      network: 'none'
    });
    
    vmId = vm.id;
    console.log(`Created VM with ID: ${vmId}`);

    // Execute a command in the VM
    console.log('Executing command in VM...');
    const result = await agent.executeInVM(vmId, 'python -c "print(2 + 2)"');
    console.log('Command result:', result.stdout.trim());

    // List all VMs to see our created VM
    console.log('Listing all VMs...');
    const vms = await agent.listVMs({ all: true });
    console.log(`Found ${vms.length} VMs total`);

    // Stop the VM
    console.log('Stopping VM...');
    await agent.stopVM(vmId);
    console.log('VM stopped');

    // Clean up the VM
    console.log('Cleaning up VM...');
    await agent.cleanVM(vmId);
    console.log('VM cleaned up');

  } catch (error) {
    console.error('Error in lifecycle example:', error.message);
    
    // Make sure to cleanup if something went wrong
    if (vmId) {
      try {
        await agent.stopVM(vmId);
        await agent.cleanVM(vmId);
        console.log('Cleaned up VM after error');
      } catch (cleanupError) {
        console.error('Error during cleanup:', cleanupError.message);
      }
    }
  }
}

vmLifecycleExample();