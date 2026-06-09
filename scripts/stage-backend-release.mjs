import { spawnSync } from 'node:child_process';
import { chmodSync, cpSync, existsSync, mkdirSync, rmSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const backendDir = path.join(root, 'symphony_elixir');
const releaseDir = path.join(backendDir, '_build', 'prod', 'rel', 'symphony_elixir');
const stagedDir = path.join(root, 'src-tauri', 'resources', 'symphony_backend');
const archivePath = path.join(root, 'src-tauri', 'resources', 'symphony_backend.tar.gz');
const binName = process.platform === 'win32' ? 'symphony_elixir.bat' : 'symphony_elixir';

function run(command, args, cwd, extraEnv = {}) {
  console.log(`> ${command} ${args.join(' ')}`);
  const result = spawnSync(command, args, {
    cwd,
    stdio: 'inherit',
    env: { ...process.env, MIX_ENV: 'prod', ...extraEnv }
  });

  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
}

if (!existsSync(path.join(backendDir, 'mix.exs'))) {
  throw new Error(`Backend mix.exs not found at ${backendDir}`);
}

run('mix', ['deps.get', '--only', 'prod'], backendDir);
run('mix', ['compile'], backendDir);
run('mix', ['release', 'symphony_elixir', '--overwrite'], backendDir);

if (!existsSync(releaseDir)) {
  throw new Error(`Mix release was not created at ${releaseDir}`);
}

rmSync(stagedDir, { recursive: true, force: true });
mkdirSync(path.dirname(stagedDir), { recursive: true });
cpSync(releaseDir, stagedDir, { recursive: true });

if (process.platform !== 'win32') {
  run('chmod', ['-R', 'u+rwX,go+rX', stagedDir], root);
}

if (process.platform === 'darwin') {
  run('xattr', ['-cr', stagedDir], root);
}

const launcher = path.join(stagedDir, 'bin', binName);
if (!existsSync(launcher)) {
  throw new Error(`Staged backend launcher missing at ${launcher}`);
}

if (process.platform !== 'win32') {
  chmodSync(launcher, 0o755);
}

rmSync(archivePath, { force: true });
run('tar', ['-czf', archivePath, '-C', path.dirname(stagedDir), path.basename(stagedDir)], root, { COPYFILE_DISABLE: '1' });

if (process.platform === 'darwin') {
  run('xattr', ['-cr', archivePath], root);
}

for (const keep of ['.gitkeep', path.join('bin', '.gitkeep'), path.join('releases', '.gitkeep')]) {
  const keepPath = path.join(stagedDir, keep);
  mkdirSync(path.dirname(keepPath), { recursive: true });
  writeFileSync(keepPath, '');
}

console.log(`Staged Symphony backend release at ${stagedDir}`);
console.log(`Packed Symphony backend archive at ${archivePath}`);
