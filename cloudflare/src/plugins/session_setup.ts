/**
 * Session Setup Orchestrator
 * Coordinates package installation and environment setup for new sessions
 */

import { SessionSetup, SetupResult } from './types';
import {
  installPipPackages,
  installNpmPackages,
  installGoModules,
  runSetupCommands,
} from './package_managers';

/**
 * Run the complete setup process for a session
 * This creates a VM, installs packages, runs commands, and extracts files
 */
export async function runSessionSetup(
  sessionId: string,
  language: string,
  setup: SessionSetup,
  env: any,
  agentStub: any
): Promise<SetupResult> {
  const startTime = Date.now();
  const result: SetupResult = {
    success: false,
    duration_ms: 0,
  };

  let vmId: string | null = null;

  try {
    // Step 1: Create temporary VM for setup
    console.log(`[Setup] Creating VM for session ${sessionId} (language: ${language})`);
    const vmCreateStart = Date.now();

    // Map TypeScript to node for setup VM (TypeScript runs on Node.js)
    const setupLanguage = language === 'typescript' ? 'node' : language;

    const createRes = await agentStub.fetch(new Request('http://agent/api/vm', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        language: setupLanguage,
        cpu_count: 1,
        memory_mib: 512, // More memory for package installs
        network_mode: 'full', // Need network for package downloads
        persist: false,
      }),
    }));

    if (!createRes.ok) {
      const error = await createRes.text();
      console.error(`[Setup] Failed to create VM:`, error);
      result.error = `Failed to create VM: ${error}`;
      return result;
    }

    const { id } = await createRes.json() as { id: string };
    vmId = id;
    console.log(`[Setup] VM created: ${vmId} (took ${Date.now() - vmCreateStart}ms)`);

    // Step 2: Install pip packages (Python)
    if (setup.pip) {
      console.log(`[Setup] Installing pip packages for ${sessionId}`);
      const pipResult = await installPipPackages(vmId, setup.pip, agentStub);

      result.pip_packages = pipResult.packages_installed;

      if (!pipResult.success) {
        result.error = 'Pip install failed';
        result.stderr = pipResult.stderr;
        result.stdout = pipResult.stdout;
        return result;
      }
    }

    // Step 3: Install npm packages (Node.js)
    if (setup.npm) {
      console.log(`[Setup] Installing npm packages for ${sessionId}`);
      const npmResult = await installNpmPackages(vmId, setup.npm, agentStub);

      result.npm_packages = npmResult.packages_installed;

      if (!npmResult.success) {
        result.error = 'npm install failed';
        result.stderr = npmResult.stderr;
        result.stdout = npmResult.stdout;
        return result;
      }
    }

    // Step 4: Install Go modules
    if (setup.go) {
      console.log(`[Setup] Installing Go modules for ${sessionId}`);
      const goResult = await installGoModules(vmId, setup.go, agentStub);

      result.go_modules = goResult.packages_installed;

      if (!goResult.success) {
        result.error = 'Go module install failed';
        result.stderr = goResult.stderr;
        result.stdout = goResult.stdout;
        return result;
      }
    }

    // Step 5: Run custom commands
    if (setup.commands && setup.commands.length > 0) {
      console.log(`[Setup] Running custom commands for ${sessionId}`);
      const cmdResult = await runSetupCommands(vmId, setup.commands, setup.envs, agentStub);

      result.commands_run = cmdResult.packages_installed; // Reusing field

      if (!cmdResult.success) {
        result.error = 'Custom command failed';
        result.stderr = cmdResult.stderr;
        result.stdout = cmdResult.stdout;
        return result;
      }
    }

    // Step 6: Extract all files to R2 (includes installed packages!)
    console.log(`[Setup] Extracting files for ${sessionId}`);
    await extractFilesToR2(vmId, sessionId, env.SESSIONS_BUCKET, agentStub);

    result.success = true;
    result.duration_ms = Date.now() - startTime;

    console.log(`[Setup] Completed successfully for ${sessionId} in ${result.duration_ms}ms`);
    return result;

  } catch (error) {
    result.error = error instanceof Error ? error.message : String(error);
    result.duration_ms = Date.now() - startTime;
    return result;

  } finally {
    // Step 7: Always cleanup the setup VM
    if (vmId) {
      console.log(`[Setup] Cleaning up VM ${vmId}`);
      await agentStub.fetch(new Request(`http://agent/api/vm/${vmId}`, {
        method: 'DELETE',
      }));
    }
  }
}

/**
 * Extract all files from VM to R2 bucket
 * This captures installed packages and any generated files
 */
async function extractFilesToR2(
  vmId: string,
  sessionId: string,
  bucket: R2Bucket,
  agentStub: any
): Promise<void> {
  // List all files in VM
  const listRes = await agentStub.fetch(new Request(`http://agent/api/vm/${vmId}/files`, {
    method: 'GET',
  }));

  if (!listRes.ok) {
    console.error('Failed to list VM files:', await listRes.text());
    return;
  }

  const { files } = await listRes.json() as { files: Array<{ path: string; size: number }> };

  // Security: Filter out sensitive files that should NOT be persisted
  const EXCLUDED_PATTERNS = [
    '.env',
    '.env.local',
    '.env.production',
    '.env.development',
    'credentials.json',
    'service-account.json',
    '.aws/credentials',
    '.ssh/id_rsa',
    '.ssh/id_ed25519',
    '.netrc',
    '.dockercfg',
    '.npmrc',
    '.pypirc',
    'secrets.json',
    'secrets.yaml',
    'secrets.yml',
  ];

  const shouldExclude = (filePath: string): boolean => {
    const lowerPath = filePath.toLowerCase();
    return EXCLUDED_PATTERNS.some(pattern => {
      const lowerPattern = pattern.toLowerCase();
      // Match exact filename or path ending with pattern
      return lowerPath === lowerPattern || lowerPath.endsWith('/' + lowerPattern);
    });
  };

  const filteredFiles = files.filter(file => !shouldExclude(file.path));
  const excludedCount = files.length - filteredFiles.length;

  if (excludedCount > 0) {
    console.log(`[Setup] Excluded ${excludedCount} sensitive files from extraction`);
  }

  console.log(`[Setup] Extracting ${filteredFiles.length} files in parallel...`);

  // Download and upload files in parallel (batches of 50 to avoid overwhelming)
  const batchSize = 50;
  for (let i = 0; i < filteredFiles.length; i += batchSize) {
    const batch = filteredFiles.slice(i, i + batchSize);

    await Promise.all(batch.map(async (file) => {
      try {
        const fileRes = await agentStub.fetch(new Request(`http://agent/api/vm/${vmId}/files/${file.path}`, {
          method: 'GET',
        }));

        if (!fileRes.ok) return;

        const content = await fileRes.arrayBuffer();

        // Upload to R2
        const key = `sessions/${sessionId}/${file.path}`;
        await bucket.put(key, content);
      } catch (error) {
        console.error(`[Setup] Failed to extract ${file.path}:`, error);
      }
    }));

    console.log(`[Setup] Extracted ${Math.min(i + batchSize, filteredFiles.length)}/${filteredFiles.length} files`);
  }

  console.log(`[Setup] Extracted ${filteredFiles.length} files to R2 for session ${sessionId}`);
}
