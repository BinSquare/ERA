/**
 * Session Setup Plugin Types
 * Defines interfaces for package installation and environment setup
 */

export interface SessionSetup {
  // Python package installation
  pip?: string[] | { requirements: string };

  // Node.js package installation
  npm?: string[] | { packageJson: string };

  // Go module installation
  go?: string[] | { goMod: string };

  // Custom shell commands (run after package installs)
  commands?: string[];

  // Environment variables for setup phase
  envs?: Record<string, string>;
}

export interface SetupResult {
  success: boolean;
  duration_ms: number;
  pip_packages?: string[];
  npm_packages?: string[];
  go_modules?: string[];
  commands_run?: string[];
  error?: string;
  stderr?: string;
  stdout?: string;
}

export interface PackageInstallResult {
  success: boolean;
  packages_installed: string[];
  duration_ms: number;
  stdout: string;
  stderr: string;
  exit_code: number;
}
