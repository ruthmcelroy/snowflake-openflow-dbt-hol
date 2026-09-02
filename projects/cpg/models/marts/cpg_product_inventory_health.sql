-- ---------------------------------------------------------------------------
-- cpg_product_inventory_health
--
-- Business-facing inventory fact. This is the supply planner's worklist: which
-- products are at risk of running out, and which are tying up capital.
--
-- Contract enforced (see _cpg__marts.yml), so every column is cast explicitly.
--
-- Grain: one row per record_id (one product occurrence).
-- ---------------------------------------------------------------------------

{{ config(materialized='table') }}

with inventory as (

    select * from {{ ref('int_cpg_inventory_health') }}

)

select

    -- ---- keys ---------------------------------------------------------------
    cast(record_id as varchar) as record_id,
    cast(product_id as varchar) as product_id,

    -- ---- time ---------------------------------------------------------------
    cast(order_date as date) as order_date,

    -- ---- dimensions ----------------------------------------------------------
    cast(product_category as varchar) as product_category,
    cast(product_subcategory as varchar) as product_subcategory,
    cast(stockout_risk_level as varchar) as stockout_risk_level,
    cast(overstock_risk_level as varchar) as overstock_risk_level,

    -- ---- measures --------------------------------------------------------------
    cast(inventory_level as number(38, 0)) as inventory_level,
    cast(demand_forecast as number(38, 0)) as demand_forecast,
    cast(inventory_coverage_ratio as number(18, 4)) as inventory_coverage_ratio,

    cast(inventory_turnover as number(9, 4)) as inventory_turnover,
    cast(stockout_rate as number(9, 6)) as stockout_rate,
    cast(overstock_rate as number(9, 6)) as overstock_rate,
    cast(product_price as number(18, 2)) as product_price,
    cast(price_elasticity as number(9, 4)) as price_elasticity,
    cast(product_rating as number(9, 4)) as product_rating,
    cast(product_review_count as number(38, 0)) as product_review_count,

    -- ---- flags -----------------------------------------------------------------
    cast(is_price_optimized as boolean) as is_price_optimized,
    cast(needs_planner_review as boolean) as needs_planner_review

from inventory
