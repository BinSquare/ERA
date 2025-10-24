/**
 * Package Manager Helpers
 * Functions to install packages via pip, npm, go, etc.
 */

import { PackageInstallResult } from './types';

/**
 * Install Python packages via pip
 */
export async function installPipPackages(
  vmId: string,
  packages: string[] | { requirements: string },
  agentStub: any
): Promise<PackageInstallResult> {
  const startTime = Date.now();

  let command: string;
  const packagesList: string[] = [];

  if (Array.isArray(packages)) {
    // Install from array: pip install requests pandas
    // Use --target to explicitly specify installation directory, avoiding site-packages scanning
    packagesList.push(...packages);
    command = `pip install --target=/home/agent/.local/lib/python3.11/site-packages ${packages.join(' ')}`;
  } else {
    // Install from requirements.txt content
    // Write requirements.txt to VM, then install
    const reqContent = packages.requirements;
    const reqBytes = new TextEncoder().encode(reqContent);

    await agentStub.fetch(new Request(`http://agent/api/vm/${vmId}/files/requirements.txt`, {
      method: 'PUT',
      body: reqBytes,
    }));

    command = 'pip install --target=/home/agent/.local/lib/python3.11/site-packages -r requirements.txt';
    // Parse package names from requirements
    packagesList.push(...reqContent.split('\n').filter(line => line.trim() && !line.startsWith('#')));
  }

  const runRes = await agentStub.fetch(new Request(`http://agent/api/vm/${vmId}/run`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ command, timeout: 300 }), // 5 min timeout for installs
  }));

  const result = await runRes.json() as {
    exit_code: number;
    stdout: string;
    stderr: string;
  };

  return {
    success: result.exit_code === 0,
    packages_installed: packagesList,
    duration_ms: Date.now() - startTime,
    stdout: result.stdout,
    stderr: result.stderr,
    exit_code: result.exit_code,
  };
}

/**
 * Install Node.js packages via npm
 */
export async function installNpmPackages(
  vmId: string,
  packages: string[] | { packageJson: string },
  agentStub: any
): Promise<PackageInstallResult> {
  const startTime = Date.now();

  let command: string;
  const packagesList: string[] = [];

  if (Array.isArray(packages)) {
    // Install from array: npm install express lodash
    packagesList.push(...packages);
    command = `npm install ${packages.join(' ')}`;
  } else {
    // Install from package.json content
    const pkgJson = packages.packageJson;
    const pkgBytes = new TextEncoder().encode(pkgJson);

    await agentStub.fetch(new Request(`http://agent/api/vm/${vmId}/files/package.json`, {
      method: 'PUT',
      body: pkgBytes,
    }));

    command = 'npm install';

    // Parse package names from package.json
    try {
      const parsed = JSON.parse(pkgJson);
      if (parsed.dependencies) {
        packagesList.push(...Object.keys(parsed.dependencies));
      }
    } catch (e) {
      console.error('Failed to parse package.json:', e);
    }
  }

  const runRes = await agentStub.fetch(new Request(`http://agent/api/vm/${vmId}/run`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ command, timeout: 300 }),
  }));

  const result = await runRes.json() as {
    exit_code: number;
    stdout: string;
    stderr: string;
  };

  return {
    success: result.exit_code === 0,
    packages_installed: packagesList,
    duration_ms: Date.now() - startTime,
    stdout: result.stdout,
    stderr: result.stderr,
    exit_code: result.exit_code,
  };
}

/**
 * Install Go modules
 */
export async function installGoModules(
  vmId: string,
  modules: string[] | { goMod: string },
  agentStub: any
): Promise<PackageInstallResult> {
  const startTime = Date.now();

  let commands: string[] = [];
  const modulesList: string[] = [];

  if (Array.isArray(modules)) {
    // Install modules: go get github.com/gin-gonic/gin
    modulesList.push(...modules);
    commands = modules.map(mod => `go get ${mod}`);
  } else {
    // Install from go.mod content
    const goModContent = modules.goMod;
    const goModBytes = new TextEncoder().encode(goModContent);

    await agentStub.fetch(new Request(`http://agent/api/vm/${vmId}/files/go.mod`, {
      method: 'PUT',
      body: goModBytes,
    }));

    commands = ['go mod download'];

    // Parse module names from go.mod
    const lines = goModContent.split('\n');
    for (const line of lines) {
      if (line.trim().startsWith('require')) {
        const match = line.match(/require\s+([^\s]+)/);
        if (match) modulesList.push(match[1]);
      }
    }
  }

  // Run all commands sequentially
  let lastResult: any = { exit_code: 0, stdout: '', stderr: '' };

  for (const command of commands) {
    const runRes = await agentStub.fetch(new Request(`http://agent/api/vm/${vmId}/run`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ command, timeout: 300 }),
    }));

    lastResult = await runRes.json();
    if (lastResult.exit_code !== 0) break;
  }

  return {
    success: lastResult.exit_code === 0,
    packages_installed: modulesList,
    duration_ms: Date.now() - startTime,
    stdout: lastResult.stdout,
    stderr: lastResult.stderr,
    exit_code: lastResult.exit_code,
  };
}

/**
 * Run custom setup commands
 */
export async function runSetupCommands(
  vmId: string,
  commands: string[],
  envs: Record<string, string> | undefined,
  agentStub: any
): Promise<PackageInstallResult> {
  const startTime = Date.now();

  let allStdout = '';
  let allStderr = '';
  let lastExitCode = 0;

  for (const command of commands) {
    const runRes = await agentStub.fetch(new Request(`http://agent/api/vm/${vmId}/run`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        command,
        timeout: 300,
        ...(envs && { envs })
      }),
    }));

    const result = await runRes.json() as {
      exit_code: number;
      stdout: string;
      stderr: string;
    };

    allStdout += result.stdout + '\n';
    allStderr += result.stderr + '\n';
    lastExitCode = result.exit_code;

    if (result.exit_code !== 0) {
      break; // Stop on first failure
    }
  }

  return {
    success: lastExitCode === 0,
    packages_installed: commands,
    duration_ms: Date.now() - startTime,
    stdout: allStdout,
    stderr: allStderr,
    exit_code: lastExitCode,
  };
}
