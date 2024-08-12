use tokio::sync::broadcast;

mod processor_connection;
mod server;
mod types;
mod util;

#[tokio::main]
async fn main() -> Result<(), ()> {
    env_logger::init();

    let processor_url = std::env::var("PROCESSOR_WS_URL").unwrap();

    let (tx, _) = broadcast::channel(2048);
    let tx2 = tx.clone();

    let processor_connection = tokio::spawn(processor_connection::processor_connection(processor_url, tx2));

    let sse_server = tokio::spawn(server::server(tx));

    tokio::select! {
        _ = processor_connection => {
            log::error!("Connection to processor error.")
        }
        _ = sse_server => {
            log::error!("SSE server error")
        }
    };

    Ok(())
}
