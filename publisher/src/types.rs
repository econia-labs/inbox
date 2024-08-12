use serde::{Deserialize, Serialize};
use strum::{Display, EnumIter, EnumString};

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

#[derive(Serialize, Deserialize, Debug, Default)]
pub struct Subscription {
    #[serde(default)]
    pub markets: Vec<u64>,
    #[serde(default)]
    pub event_types: Vec<EventType>,
}

#[derive(Deserialize, Serialize, Clone, Debug)]
pub struct DbEvent {
    pub sequence_number: i64,
    pub creation_number: i64,
    pub account_address: String,
    pub transaction_version: i64,
    pub transaction_block_height: i64,
    pub type_: String,
    pub data: serde_json::Value,
    pub event_index: i64,
    pub indexed_type: String,
}
