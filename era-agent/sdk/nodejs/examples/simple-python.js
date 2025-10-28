// Example 1: Simple Python execution in ephemeral VM
const ERAAgent = require('../index.js');

async function simplePythonExample() {
  console.log('=== Simple Python Example ===');
  
  const agent = new ERAAgent({
    agentPath: '../../../agent', // Adjust path based on your setup
    env: process.env // Use existing environment
  });

  try {
    // Run a simple Python command in a temporary VM
    const result = await agent.runTemp('python', 'python -c "print(\'Hello from ephemeral Python VM!\')"', {
      cpu: 1,
      mem: 256,
      timeout: 30
    });
    
    console.log('Command output:', result.stdout.trim());
    console.log('Exit code:', result.exitCode);
  } catch (error) {
    console.error('Error:', error.message);
  }
}

simplePythonExample();