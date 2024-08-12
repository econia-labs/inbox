use std::str::FromStr;

use crate::types::{DbEvent, EventType, Subscription};

/// Get the EventType of a DbEvent
pub fn get_event_type(event: &DbEvent) -> Result<EventType, String> {
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
pub fn get_market_id(event: &DbEvent, event_type: EventType) -> Result<u64, String> {
    match event_type {
        EventType::Swap | EventType::Liquidity => {
            let market_id = event.data.get("market_id").map(|e| e.as_str()).flatten();
            if let Some(market_id) = market_id {
                if let Ok(market_id) = market_id.parse() {
                    Ok(market_id)
                } else {
                    Err(format!("Got event {event_type} but market_id is not a number: {event:#?}"))
                }
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
                .map(|e| e.as_str())
                .flatten();
            if let Some(market_id) = market_id {
                if let Ok(market_id) = market_id.parse() {
                    Ok(market_id)
                } else {
                    Err(format!("Got event {event_type} but market_id is not a number: {event:#?}"))
                }
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
pub fn is_match(subscription: &Subscription, event: &DbEvent) -> bool {
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
