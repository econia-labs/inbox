use std::{convert::Infallible, str::FromStr, sync::Arc};

use axum::{extract::State, response::{sse::{Event, KeepAlive}, Sse}, routing::get, Router};
use axum_extra::extract::Query;
use futures_util::{Stream, StreamExt};
use serde::{Deserialize, Serialize};
use strum::{Display, EnumIter, EnumString};
use tokio::sync::broadcast::{error::RecvError, Sender};

use crate::types::DbEvent;

struct AppState {
    tx: Sender<DbEvent>,
}

#[derive(Serialize, Deserialize, Debug, EnumString, EnumIter, PartialEq, Eq, Display)]
pub enum EventType {
    Chat,
    Swap,
    Liquidity,
    State,
    GlobalState,
    PeriodicState,
    MarketRegistration,
}

#[derive(Serialize, Deserialize, Debug)]
pub struct Subscription {
    #[serde(default)]
    pub markets: Vec<u64>,
    #[serde(default)]
    pub event_types: Vec<EventType>,
}

/// Get the EventType of a DbEvent
fn get_event_type(event: &DbEvent) -> Result<EventType, String> {
    let event_name = event.indexed_type.split("::").last();
    if event_name.is_none() {
        return Err(format!("Got invalid event type: {}", event.indexed_type));
    }
    let event_name = event_name.unwrap();
    let event_type = EventType::from_str(event_name);
    if event_type.is_err() {
        return Err(format!(
            "Got unknown event type: {}, error: {}",
            event.indexed_type,
            event_type.unwrap_err(),
        ));
    }
    return Ok(event_type.unwrap())
}

/// Get the market ID of a DbEvent of a given EventType
fn get_market_id(event: &DbEvent, event_type: EventType) -> Result<u64, String> {
    match event_type {
        EventType::Swap | EventType::Liquidity => {
            let market_id = event.data.get("market_id").map(|e| e.as_u64()).flatten();
            if let Some(market_id) = market_id {
                Ok(market_id)
            } else {
                Err(format!("Got event {event_type} with unknown format: {event:#?}"))
            }
        }
        EventType::Chat | EventType::State | EventType::PeriodicState | EventType::MarketRegistration => {
            let market_id = event
                .data
                .get("market_metadata")
                .map(|e| e.get("market_id"))
                .flatten()
                .map(|e| e.as_u64())
                .flatten();
            if let Some(market_id) = market_id {
                Ok(market_id)
            } else {
                Err(format!("Got event {event_type} with unknown format: {event:#?}"))
            }
        },
        EventType::GlobalState => {
            Err(format!("Got event {event_type} which does not have a market ID"))
        }
    }
}

/// Returns true if the given subscription should receive the given event.
fn is_match(subscription: &Subscription, event: &DbEvent) -> bool {
    // If all fields of a subscription are empty, all events should be sent there.
    if subscription.markets.is_empty() && subscription.event_types.is_empty() {
        return true;
    }

    let event_type = match get_event_type(event) {
        Ok(event_type) => event_type,
        Err(msg) => {
            log::error!("{msg}");
            return false;
        }
    };

    if !subscription.event_types.is_empty() && !subscription.event_types.contains(&event_type) {
        return false;
    }
    if subscription.markets.is_empty() {
        return true;
    }
    if event_type == EventType::GlobalState {
        return true;
    }

    match get_market_id(event, event_type) {
        Ok(market_id) => subscription.markets.contains(&market_id),
        Err(msg) => {
            log::error!("{msg}");
            false
        }
    }
}

/// Handles a request to `/sse`.
///
/// Takes subscription data as query parameters.
///
/// If a field is left empty, you will be subscribed to all.
///
/// Example of connection paths:
///
/// - `/sse?markets=1&event_types=Chat`: subscribe to chat events on market 1
/// - `/sse?markets=1`: subscribe to all events on market 1
/// - `/sse?event_types=State`: subscribe to all State events
/// - `/sse`: subscribe to all events
/// - `/sse?markets=1&markets=2&event_types=Chat&event_types=Swap`: subscribe to Chat and Swap events on markets 1 and 2
async fn sse_handler(
    Query(subscription): Query<Subscription>,
    State(state): State<Arc<AppState>>,
) -> Sse<impl Stream<Item = Result<Event, Infallible>>> {
    let mut rx = state.tx.subscribe();
    let stream = async_stream::stream! {
        loop {
            let mut r = rx.recv().await;
            while matches!(r, Err(RecvError::Lagged(_))) {
                log::warn!("Messages dropped due to lag.");
                r = rx.recv().await;
            }
            if let Ok(item) = r {
                if is_match(&subscription, &item) {
                    yield item;
                }
            } else {
                log::error!("Got error: {}", r.unwrap_err());
            }
        }
    };

    let stream = stream
        .map(|e| Event::default().data(serde_json::to_string(&e).unwrap()))
        .map(Ok);

    Sse::new(stream).keep_alive(KeepAlive::default())
}

pub async fn sse_server(tx: Sender<DbEvent>) {
    let app_state = AppState { tx };

    let app = Router::new()
        .route("/sse", get(sse_handler))
        .with_state(Arc::new(app_state));

    let listener = tokio::net::TcpListener::bind("0.0.0.0:3009").await.unwrap();
    axum::serve(listener, app).await.unwrap();
}
