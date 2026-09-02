-- ---------------------------------------------------------------------------
-- RENAME THIS FILE to <track_key>_time_spine.sql
--
-- One row per calendar day. The semantic layer requires a time spine at DAY
-- granularity or smaller before it will serve any metric that has a time
-- dimension. If your track has even one <date_column> dimension, you need
-- this model, or dbt platform commands (including dbt seed, since it
-- validates the semantic manifest before running anything) fail with:
-- "The semantic layer requires a time spine model with granularity DAY or
-- smaller."
--
-- Range is wide on purpose so it comfortably covers seed data and years of
-- future demo runs without needing to be touched again.
-- ---------------------------------------------------------------------------

{{ config(materialized='table') }}

with base_dates as (
    {{ dbt.date_spine(
        'day',
        "cast('2015-01-01' as date)",
        "cast('2035-01-01' as date)"
    ) }}
)

select
    cast(date_day as date) as date_day
from base_dates
