CREATE INDEX inbox_events_mypools ON inbox_events (
    (data ->> 'provider')
) WHERE event_name = 'emojicoin_dot_fun::Liquidity' AND (data ->> 'liquidity_provided')::BOOLEAN = true;

-- noqa: disable=PRS
CREATE FUNCTION mypools (address text) RETURNS TABLE (LIKE market_data) AS
$$
  WITH mypools AS (
    SELECT DISTINCT (data ->> 'market_id')::NUMERIC AS market_id
    FROM inbox_events
    WHERE event_name = 'emojicoin_dot_fun::Liquidity'
    AND (data ->> 'liquidity_provided')::BOOLEAN = true
    AND (data ->> 'provider') = $1
  )
  SELECT m.* FROM market_data m INNER JOIN mypools p ON m.market_id = p.market_id;
$$ LANGUAGE SQL;
