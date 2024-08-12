use std::sync::Arc;

use axum::{routing::get, Router};
use tokio::sync::broadcast::Sender;

use crate::types::DbEvent;

#[cfg(feature = "ws")]
mod ws;
#[cfg(feature = "sse")]
mod sse;

struct AppState {
    #[allow(dead_code)]
    tx: Sender<DbEvent>,
}

#[cfg(all(feature = "sse", not(feature = "ws")))]
fn prepare_app(app: Router<Arc<AppState>>) -> Router<Arc<AppState>> {
    app.route("/sse", get(sse::handler))
}

#[cfg(all(feature = "ws", not(feature = "sse")))]
fn prepare_app(app: Router<Arc<AppState>>) -> Router<Arc<AppState>> {
    app.route("/ws", get(ws::handler))
}

#[cfg(all(feature = "ws", feature = "sse"))]
fn prepare_app(app: Router<Arc<AppState>>) -> Router<Arc<AppState>> {
    app
        .route("/ws", get(ws::handler))
        .route("/sse", get(sse::handler))
}

#[cfg(all(not(feature = "ws"), not(feature = "sse")))]
fn prepare_app(app: Router<Arc<AppState>>) -> Router<Arc<AppState>> {
    app
}

async fn health() {}

pub async fn server(tx: Sender<DbEvent>) {
    let app_state = AppState { tx };

    let app = prepare_app(Router::new().route("/", get(health)));
    let app = app.with_state(Arc::new(app_state));

    let listener = tokio::net::TcpListener::bind("0.0.0.0:3009").await.unwrap();
    axum::serve(listener, app).await.unwrap();
}
