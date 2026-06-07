#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

#[tauri::command]
fn default_api_base_url() -> String {
    "http://127.0.0.1:4004".to_string()
}

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_store::Builder::new().build())
        .plugin(tauri_plugin_notification::init())
        .invoke_handler(tauri::generate_handler![default_api_base_url])
        .run(tauri::generate_context!())
        .expect("error while running Symphony Console");
}
