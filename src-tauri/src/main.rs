#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use serde::Serialize;
use std::{
    fs::{self, OpenOptions},
    io::{Read, Write},
    net::{TcpListener, TcpStream},
    path::{Path, PathBuf},
    process::{Child, Command, Stdio},
    sync::Mutex,
    thread,
    time::{Duration, Instant},
};
use tauri::{Manager, State};

const PREFERRED_PORT: u16 = 4004;

struct BackendProcess {
    child: Mutex<Option<Child>>,
    info: Mutex<Option<BackendInfo>>,
    log_path: Mutex<Option<PathBuf>>,
    last_error: Mutex<Option<String>>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct BackendInfo {
    base_url: String,
    host: String,
    port: u16,
    source: String,
    healthy: bool,
    managed: bool,
    pid: Option<u32>,
    log_path: Option<String>,
    last_error: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct BackendLogs {
    log_path: Option<String>,
    text: String,
}

fn base_url(port: u16) -> String {
    format!("http://127.0.0.1:{port}")
}

fn port_is_free(port: u16) -> bool {
    TcpListener::bind(("127.0.0.1", port)).is_ok()
}

fn choose_port() -> Result<u16, String> {
    if port_is_free(PREFERRED_PORT) {
        return Ok(PREFERRED_PORT);
    }
    let listener = TcpListener::bind(("127.0.0.1", 0)).map_err(|e| e.to_string())?;
    let port = listener.local_addr().map_err(|e| e.to_string())?.port();
    Ok(port)
}

fn probe_health(port: u16) -> bool {
    let mut stream = match TcpStream::connect_timeout(
        &format!("127.0.0.1:{port}").parse().unwrap(),
        Duration::from_millis(650),
    ) {
        Ok(s) => s,
        Err(_) => return false,
    };
    let _ = stream.set_read_timeout(Some(Duration::from_millis(650)));
    let _ = stream.set_write_timeout(Some(Duration::from_millis(650)));
    if stream
        .write_all(b"GET /healthz HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n")
        .is_err()
    {
        return false;
    }
    let mut buf = String::new();
    if stream.read_to_string(&mut buf).is_err() {
        return false;
    }
    buf.starts_with("HTTP/1.1 200") || buf.starts_with("HTTP/1.0 200")
}

fn wait_for_health(port: u16, timeout: Duration) -> bool {
    let start = Instant::now();
    while start.elapsed() < timeout {
        if probe_health(port) {
            return true;
        }
        thread::sleep(Duration::from_millis(250));
    }
    false
}

fn backend_resource_dir(app: &tauri::AppHandle) -> Result<PathBuf, String> {
    let resource_dir = app.path().resource_dir().map_err(|e| e.to_string())?;
    let direct = resource_dir.join("symphony_backend");
    if direct.exists() {
        return Ok(direct);
    }
    let dev = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("resources/symphony_backend");
    if dev.exists() {
        return Ok(dev);
    }
    Err(format!(
        "Bundled backend release not found. Looked in {} and {}",
        direct.display(),
        dev.display()
    ))
}

fn backend_executable(dir: &Path) -> PathBuf {
    if cfg!(windows) {
        dir.join("bin").join("symphony_elixir.bat")
    } else {
        dir.join("bin").join("symphony_elixir")
    }
}

fn app_log_path(app: &tauri::AppHandle) -> Result<PathBuf, String> {
    let dir = app.path().app_log_dir().map_err(|e| e.to_string())?;
    fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    Ok(dir.join("symphony-backend.log"))
}

fn append_log(path: &Path, line: &str) {
    if let Ok(mut file) = OpenOptions::new().create(true).append(true).open(path) {
        let _ = writeln!(file, "{line}");
    }
}

fn spawn_pipe_reader<R: Read + Send + 'static>(mut reader: R, log_path: PathBuf, prefix: &'static str) {
    thread::spawn(move || {
        let mut buf = [0_u8; 4096];
        loop {
            match reader.read(&mut buf) {
                Ok(0) => break,
                Ok(n) => {
                    let text = String::from_utf8_lossy(&buf[..n]);
                    for line in text.lines() {
                        append_log(&log_path, &format!("[{prefix}] {line}"));
                    }
                }
                Err(_) => break,
            }
        }
    });
}

fn status_from_state(state: &BackendProcess) -> BackendInfo {
    let info = state.info.lock().unwrap().clone();
    let err = state.last_error.lock().unwrap().clone();
    match info {
        Some(mut i) => {
            i.healthy = probe_health(i.port);
            i.last_error = err;
            i
        }
        None => BackendInfo {
            base_url: base_url(PREFERRED_PORT),
            host: "127.0.0.1".to_string(),
            port: PREFERRED_PORT,
            source: "not-started".to_string(),
            healthy: probe_health(PREFERRED_PORT),
            managed: false,
            pid: None,
            log_path: state
                .log_path
                .lock()
                .unwrap()
                .as_ref()
                .map(|p| p.to_string_lossy().to_string()),
            last_error: err,
        },
    }
}

#[tauri::command]
fn backend_status(state: State<'_, BackendProcess>) -> BackendInfo {
    status_from_state(&state)
}

#[tauri::command]
fn ensure_backend_ready(app: tauri::AppHandle, state: State<'_, BackendProcess>) -> Result<BackendInfo, String> {
    if let Some(info) = state.info.lock().unwrap().clone() {
        if probe_health(info.port) {
            return Ok(status_from_state(&state));
        }
    }

    let mut child_lock = state.child.lock().unwrap();
    if child_lock.is_some() {
        drop(child_lock);
        return Ok(status_from_state(&state));
    }

    let port = choose_port()?;
    let backend_dir = backend_resource_dir(&app)?;
    let executable = backend_executable(&backend_dir);
    if !executable.exists() {
        let msg = format!("Bundled backend executable not found: {}", executable.display());
        *state.last_error.lock().unwrap() = Some(msg.clone());
        return Err(msg);
    }

    let app_data_dir = app.path().app_data_dir().map_err(|e| e.to_string())?;
    fs::create_dir_all(&app_data_dir).map_err(|e| e.to_string())?;
    let workflow_path = app_data_dir.join("WORKFLOW.md");
    let workspace_root = app_data_dir.join("symphony_workspaces");
    fs::create_dir_all(&workspace_root).map_err(|e| e.to_string())?;
    let log_path = app_log_path(&app)?;
    append_log(&log_path, &format!("--- starting bundled backend on {} ---", base_url(port)));
    append_log(&log_path, &format!("backend_dir={} executable={}", backend_dir.display(), executable.display()));

    let mut command = if cfg!(windows) {
        let mut c = Command::new("cmd");
        c.arg("/C").arg(&executable).arg("foreground");
        c
    } else {
        let mut c = Command::new(&executable);
        c.arg("foreground");
        c
    };

    command
        .current_dir(&backend_dir)
        .env("MIX_ENV", "prod")
        .env("SYMPHONY_DESKTOP", "1")
        .env("SYMPHONY_HTTP_ENABLED", "true")
        .env("SYMPHONY_HTTP_HOST", "127.0.0.1")
        .env("SYMPHONY_HTTP_PORT", port.to_string())
        .env("PORT", port.to_string())
        .env("SYMPHONY_WORKFLOW_PATH", workflow_path.to_string_lossy().to_string())
        .env("SYMPHONY_WORKSPACE_ROOT", workspace_root.to_string_lossy().to_string())
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());

    let mut child = command.spawn().map_err(|e| {
        let msg = format!("failed to spawn bundled backend: {e}");
        *state.last_error.lock().unwrap() = Some(msg.clone());
        msg
    })?;
    let pid = child.id();
    if let Some(stdout) = child.stdout.take() {
        spawn_pipe_reader(stdout, log_path.clone(), "stdout");
    }
    if let Some(stderr) = child.stderr.take() {
        spawn_pipe_reader(stderr, log_path.clone(), "stderr");
    }

    *child_lock = Some(child);
    *state.log_path.lock().unwrap() = Some(log_path.clone());
    *state.info.lock().unwrap() = Some(BackendInfo {
        base_url: base_url(port),
        host: "127.0.0.1".to_string(),
        port,
        source: "bundled-mix-release".to_string(),
        healthy: false,
        managed: true,
        pid: Some(pid),
        log_path: Some(log_path.to_string_lossy().to_string()),
        last_error: None,
    });

    if !wait_for_health(port, Duration::from_secs(20)) {
        let msg = format!("Bundled backend did not become healthy at {}", base_url(port));
        append_log(&log_path, &msg);
        *state.last_error.lock().unwrap() = Some(msg.clone());
        return Err(msg);
    }

    append_log(&log_path, "--- bundled backend healthy ---");
    Ok(status_from_state(&state))
}

#[tauri::command]
fn backend_stop(state: State<'_, BackendProcess>) -> BackendInfo {
    if let Some(mut child) = state.child.lock().unwrap().take() {
        let _ = child.kill();
        let _ = child.wait();
    }
    *state.info.lock().unwrap() = None;
    status_from_state(&state)
}

#[tauri::command]
fn backend_restart(app: tauri::AppHandle, state: State<'_, BackendProcess>) -> Result<BackendInfo, String> {
    let _ = backend_stop(state.clone());
    ensure_backend_ready(app, state)
}

#[tauri::command]
fn backend_logs(state: State<'_, BackendProcess>, max_bytes: Option<usize>) -> Result<BackendLogs, String> {
    let path = state.log_path.lock().unwrap().clone();
    let Some(path) = path else {
        return Ok(BackendLogs { log_path: None, text: String::new() });
    };
    let bytes = fs::read(&path).map_err(|e| e.to_string())?;
    let max = max_bytes.unwrap_or(64 * 1024);
    let start = bytes.len().saturating_sub(max);
    Ok(BackendLogs {
        log_path: Some(path.to_string_lossy().to_string()),
        text: String::from_utf8_lossy(&bytes[start..]).to_string(),
    })
}

#[tauri::command]
fn default_api_base_url(app: tauri::AppHandle, state: State<'_, BackendProcess>) -> Result<String, String> {
    Ok(ensure_backend_ready(app, state)?.base_url)
}

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_store::Builder::new().build())
        .plugin(tauri_plugin_notification::init())
        .manage(BackendProcess {
            child: Mutex::new(None),
            info: Mutex::new(None),
            log_path: Mutex::new(None),
            last_error: Mutex::new(None),
        })
        .invoke_handler(tauri::generate_handler![
            default_api_base_url,
            ensure_backend_ready,
            backend_status,
            backend_stop,
            backend_restart,
            backend_logs
        ])
        .on_window_event(|window, event| {
            if let tauri::WindowEvent::CloseRequested { .. } = event {
                let state = window.state::<BackendProcess>();
                let _ = backend_stop(state);
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running Symphony Console");
}
