import { randomBytes } from "node:crypto";
import {
  existsSync,
  mkdirSync,
  readFileSync,
  writeFileSync,
} from "node:fs";
import { homedir } from "node:os";
import { join, resolve } from "node:path";
import { expandHomePath } from "./roots.js";

export interface CloudspaceUserConfig {
  host?: string;
  port?: number;
  allowedRoots?: string[];
  publicBaseUrl?: string | null;
  allowedHosts?: string[];
  stateDir?: string;
  worktreeRoot?: string;
  agentDir?: string;
}

export interface CloudspaceAuthConfig {
  ownerToken?: string;
}

export interface CloudspaceFiles {
  dir: string;
  configPath: string;
  authPath: string;
  configExists: boolean;
  authExists: boolean;
  config: CloudspaceUserConfig;
  auth: CloudspaceAuthConfig;
}

export function cloudspaceConfigDir(env: NodeJS.ProcessEnv = process.env): string {
  return resolve(expandHomePath(env.CLOUDSPACE_CONFIG_DIR ?? join(homedir(), ".cloudspace")));
}

export function cloudspaceConfigPath(env: NodeJS.ProcessEnv = process.env): string {
  return join(cloudspaceConfigDir(env), "config.json");
}

export function cloudspaceAuthPath(env: NodeJS.ProcessEnv = process.env): string {
  return join(cloudspaceConfigDir(env), "auth.json");
}

export function loadCloudspaceFiles(env: NodeJS.ProcessEnv = process.env): CloudspaceFiles {
  const dir = cloudspaceConfigDir(env);
  const configPath = join(dir, "config.json");
  const authPath = join(dir, "auth.json");
  const configExists = existsSync(configPath);
  const authExists = existsSync(authPath);

  return {
    dir,
    configPath,
    authPath,
    configExists,
    authExists,
    config: configExists ? readJsonFile<CloudspaceUserConfig>(configPath) : {},
    auth: authExists ? readJsonFile<CloudspaceAuthConfig>(authPath) : {},
  };
}

export function writeCloudspaceConfig(
  config: CloudspaceUserConfig,
  env: NodeJS.ProcessEnv = process.env,
): string {
  const filePath = cloudspaceConfigPath(env);
  mkdirSync(cloudspaceConfigDir(env), { recursive: true });
  writeJsonFile(filePath, config, 0o600);
  return filePath;
}

export function writeCloudspaceAuth(
  auth: CloudspaceAuthConfig,
  env: NodeJS.ProcessEnv = process.env,
): string {
  const filePath = cloudspaceAuthPath(env);
  mkdirSync(cloudspaceConfigDir(env), { recursive: true });
  writeJsonFile(filePath, auth, 0o600);
  return filePath;
}

export function generateOwnerToken(): string {
  return randomBytes(32).toString("base64url");
}

function readJsonFile<T>(filePath: string): T {
  try {
    return JSON.parse(readFileSync(filePath, "utf8")) as T;
  } catch (error) {
    const reason = error instanceof Error ? error.message : String(error);
    throw new Error(`Unable to read ${filePath}: ${reason}`);
  }
}

function writeJsonFile(filePath: string, value: unknown, mode: number): void {
  writeFileSync(filePath, JSON.stringify(value, null, 2) + "\n", { mode });
}
