-- migrations/00001_add_get_top_markets_function.sql

-- Function to get the top markets by market_cap
CREATE OR REPLACE FUNCTION get_top_markets(
    module_address text
)
RETURNS TABLE (
    transaction_version bigint,
    data jsonb
) AS $$
BEGIN
    RETURN QUERY
    WITH latest_entries AS (
        SELECT DISTINCT ON (e.data->'market_metadata'->'market_id') e.*
        FROM public.inbox_events e
        WHERE e.type = module_address || '::emojicoin_dot_fun::State'
        ORDER BY e.data->'market_metadata'->'market_id', (e.data->'last_swap'->>'time')::bigint DESC
    )
    SELECT
        le.transaction_version,
        le.data
    FROM latest_entries le
    ORDER BY (le.data->'instantaneous_stats'->>'market_cap')::bigint DESC;
END;
$$ LANGUAGE plpgsql;
