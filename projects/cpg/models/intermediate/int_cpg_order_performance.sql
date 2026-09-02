-- ---------------------------------------------------------------------------
-- int_cpg_order_performance
--
-- Order-grain derived logic. Everything a commercial analyst would want to
-- slice orders by, computed once here so the mart and the semantic layer both
-- read the same definitions.
--
-- Grain: one row per record_id (one order line).
-- ---------------------------------------------------------------------------

{{ config(materialized='view') }}

with orders as (

    select * from {{ ref('stg_cpg_records') }}

),

classified as (

    select
        record_id,
        order_id,
        customer_id,
        product_id,
        order_date,

        -- ---- dimensions carried through -----------------------------------
        order_status,
        customer_segment,
        product_category,
        product_subcategory,

        -- ---- facts ----------------------------------------------------------
        order_total,
        product_price,
        product_rating,
        product_review_count,
        revenue_growth_rate,
        customer_satisfaction_rate,

        customer_lifetime_value,


        -- ---- derived: commercial banding -------------------------------------
        -- Order size band. Thresholds are the ones the commercial team uses in
        -- their weekly trading review, so they are business definitions rather
        -- than statistical quantiles.
        case
            when order_total >= 500 then 'Large'
            when order_total >= 200 then 'Medium'
            else 'Small'
        end as order_value_band,

        -- ---- derived: order lifecycle -----------------------------------------
        -- An order counts as fulfilled once it has shipped. Cancelled orders are
        -- excluded from revenue but kept in the table so cancellation rate can
        -- still be measured.
        case
            when order_status in ('Delivered', 'Shipped') then true
            else false
        end as is_fulfilled_order,

        case
            when order_status = 'Cancelled' then true
            else false
        end as is_cancelled_order,

        -- Revenue recognised only on fulfilled orders.
        case
            when order_status in ('Delivered', 'Shipped') then order_total
            else 0
        end as recognised_revenue,

        -- ---- derived: units implied by the order ------------------------------
        -- order_total / product_price gives the implied units on the line.
        -- nullif() guards against a zero price, which would otherwise divide by
        -- zero and fail the whole model.
        round(order_total / nullif(product_price, 0), 2) as implied_units

    from orders

)

select * from classified
