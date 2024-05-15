use std::{sync::Arc, time::Duration};

use anyhow::Result;
use rumqttc::{AsyncClient, EventLoop, MqttOptions, QoS, Transport};
use serde::{Deserialize, Serialize};
use sqlx_postgres::PgListener;
use tokio::sync::RwLock;

#[derive(Serialize, Deserialize)]
struct Event {
    topic: String,
    payload: serde_json::Value,
}

#[tokio::main]
async fn main() -> Result<()> {
    let mqtt_url = std::env::var("MQTT_URL")?;
    let mqtt_password = std::env::var("MQTT_PASSWORD")?;
    let db_url = std::env::var("DATABASE_URL")?;

    let mut mqttoptions =
        MqttOptions::parse_url(format!("{mqtt_url}/?client_id=mqtt_publisher")).unwrap();
    mqttoptions.set_credentials("mqtt_publisher", mqtt_password);
    mqttoptions.set_transport(Transport::Tcp);
    mqttoptions.set_keep_alive(Duration::from_secs(5));
    let (client, eventloop) = AsyncClient::new(mqttoptions, 10);

    let mqtt_client = Arc::new(RwLock::new(client));

    let pnl = postgres_notif_loop(&db_url, mqtt_client.clone());
    let epl = eventpoll_loop(eventloop);
    tokio::try_join!(epl, pnl)?;

    Ok(())
}

async fn eventpoll_loop(mut eventloop: EventLoop) -> Result<()> {
    loop {
        eventloop.poll().await.unwrap();
    }
}

async fn postgres_notif_loop(
    db_url: &str,
    mqtt_client: Arc<RwLock<AsyncClient>>,
) -> anyhow::Result<()> {
    let mut listener = PgListener::connect(db_url).await?;
    listener.listen_all(vec!["inbox_event"]).await?;
    loop {
        let notification = listener.recv().await?;
        let mqtt_client = mqtt_client.read().await;
        if notification.channel() == "inbox_event" {
            let event: serde_json::Result<Event> = serde_json::from_str(notification.payload());
            if let Ok(event) = event {
                mqtt_client
                    .publish(
                        event.topic,
                        QoS::AtLeastOnce,
                        false,
                        serde_json::to_string(&event.payload)?,
                    )
                    .await?;
            } else {
                eprintln!("Got notification on inbox_event that cannot be deserialized to an Event struct {}.", notification.payload());
                eprintln!(
                    "Please refer to the Inbox documentation on how to create events for MQTT."
                );
            }
        }
    }
}
