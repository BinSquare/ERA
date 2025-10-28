// Example 3: File staging example
const ERAAgent = require('../index.js');
const fs = require('fs');
const path = require('path');

async function fileStagingExample() {
  console.log('=== File Staging Example ===');
  
  const agent = new ERAAgent({
    agentPath: '../../../agent', // Adjust path based on your setup
    env: {
      ...process.env,
      AGENT_ENABLE_GUEST_VOLUMES: '1' // Required for file staging
    }
  });

  let vmId;
  
  try {
    // Create a temporary Python script
    const scriptContent = `
import json
data = {"message": "Hello from staged file!", "timestamp": 12345}
print(json.dumps(data, indent=2))
`;
    
    const tempScriptPath = path.join(__dirname, 'temp_script.py');
    fs.writeFileSync(tempScriptPath, scriptContent);
    console.log(`Created temporary script: ${tempScriptPath}`);

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

    // Execute the staged file in the VM
    console.log('Executing staged file in VM...');
    const result = await agent.executeInVM(vmId, 'python /in/temp_script.py', {
      file: tempScriptPath
    });
    
    console.log('Script output:', result.stdout.trim());

    // Clean up the temporary file
    fs.unlinkSync(tempScriptPath);
    console.log('Cleaned up temporary file');

    // Clean up the VM
    console.log('Cleaning up VM...');
    await agent.stopVM(vmId);
    await agent.cleanVM(vmId);
    console.log('VM cleaned up');

  } catch (error) {
    console.error('Error in file staging example:', error.message);
    
    // Cleanup if needed
    if (vmId) {
      try {
        await agent.stopVM(vmId);
        await agent.cleanVM(vmId);
      } catch (cleanupError) {
        console.error('Error during cleanup:', cleanupError.message);
      }
    }
  }
}

fileStagingExample();