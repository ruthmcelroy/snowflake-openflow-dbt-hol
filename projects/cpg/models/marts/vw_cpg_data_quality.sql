-- ---------------------------------------------------------------------------
-- vw_cpg_data_quality
--
-- A composite data-quality scorecard, one row per product category.
--
-- This is the model the lab uses to tour dbt Studio and Fusion. It is built
-- from a chain of small CTEs on purpose: each one is short enough to read, and
-- each one can be previewed on its own in dbt Studio without running the whole
-- model. Hover any column to see the type Fusion inferred, and break a ref() to
-- watch the error appear before you run anything.
--
-- The score is out of 100 and is the simple average of three dimensions:
--   completeness  - are the fields we need actually populated?
--   validity      - are the values inside the range the business expects?
--   consistency   - do fields that should agree with each other actually agree?
--
-- Grain: one row per product_category.
-- ---------------------------------------------------------------------------

{{ config(materialized='view') }}

with base as (

    select * from {{ ref('stg_cpg_records') }}

),

-- ---- completeness ---------------------------------------------------------
-- Every field a merchandising report needs should be populated. Blank strings
-- count as missing, not just NULLs, because the raw feed encodes blanks as
-- an empty string rather than a null.
completeness as (

    select
        product_category,
        count(*) as total_rows,
        count(*) - count(product_subcategory) as missing_subcategory,
        sum(case when product_subcategory is null or trim(product_subcategory) = '' then 1 else 0 end) as blank_subcategory,
        sum(case when price_optimization_recommendation is null or trim(price_optimization_recommendation) = '' then 1 else 0 end) as blank_recommendation,
        sum(case when customer_segment is null or trim(customer_segment) = '' then 1 else 0 end) as blank_segment
    from base
    group by product_category

),

-- ---- validity ---------------------------------------------------------------
-- Values that are present but outside the range the business defines. A rating
-- of 7 on a 1-5 scale is present, but it is not valid.
validity as (

    select
        product_category,
        sum(case when product_rating < 1 or product_rating > 5 then 1 else 0 end) as rating_out_of_range,
        sum(case when stockout_rate < 0 or stockout_rate > 1 then 1 else 0 end) as stockout_rate_out_of_range,
        sum(case when overstock_rate < 0 or overstock_rate > 1 then 1 else 0 end) as overstock_rate_out_of_range,
        sum(case when order_total <= 0 then 1 else 0 end) as non_positive_order_total,
        sum(case when product_price <= 0 then 1 else 0 end) as non_positive_price
    from base
    group by product_category

),

-- ---- consistency -------------------------------------------------------------
-- Fields that are individually fine but contradict each other. These are the
-- interesting ones: they are invisible to a column-by-column check and they are
-- exactly what breaks a metric later.
consistency as (

    select
        product_category,

        -- A cancelled order that still carries a value will inflate revenue for
        -- anyone who sums order_total instead of recognised_revenue.
        sum(case when order_status = 'Cancelled' and order_total > 0 then 1 else 0 end) as cancelled_with_value,

        -- A five-star average from three reviews is not the same evidence as a
        -- five-star average from three hundred.
        sum(case when product_rating > 4.5 and product_review_count < 10 then 1 else 0 end) as low_confidence_rating,

        -- A price recommendation dated after the order it supposedly influenced.
        sum(case when order_date > price_optimization_date then 1 else 0 end) as order_predates_optimisation

    from base
    group by product_category

),

-- ---- scoring ------------------------------------------------------------------
-- Each dimension starts at 100 and loses the percentage of rows that failed it.
scored as (

    select
        completeness.product_category,
        completeness.total_rows,

        completeness.blank_subcategory,
        completeness.blank_recommendation,
        completeness.blank_segment,
        validity.rating_out_of_range,
        validity.non_positive_order_total,
        consistency.cancelled_with_value,
        consistency.low_confidence_rating,
        consistency.order_predates_optimisation,

        round(
            100 - (
                100.0
                * (completeness.blank_subcategory + completeness.blank_recommendation + completeness.blank_segment)
                / nullif(completeness.total_rows * 3, 0)
            ),
            2
        ) as completeness_score,

        round(
            100 - (
                100.0
                * (
                    validity.rating_out_of_range
                    + validity.stockout_rate_out_of_range
                    + validity.overstock_rate_out_of_range
                    + validity.non_positive_order_total
                    + validity.non_positive_price
                )
                / nullif(completeness.total_rows * 5, 0)
            ),
            2
        ) as validity_score,

        round(
            100 - (
                100.0
                * (
                    consistency.cancelled_with_value
                    + consistency.low_confidence_rating
                    + consistency.order_predates_optimisation
                )
                / nullif(completeness.total_rows * 3, 0)
            ),
            2
        ) as consistency_score

    from completeness
    inner join validity
        on completeness.product_category = validity.product_category
    inner join consistency
        on completeness.product_category = consistency.product_category

),

-- ---- final -----------------------------------------------------------------
final as (

    select
        product_category,
        total_rows,
        completeness_score,
        validity_score,
        consistency_score,

        round((completeness_score + validity_score + consistency_score) / 3, 2) as data_quality_score,

        case
            when (completeness_score + validity_score + consistency_score) / 3 >= 95 then 'A'
            when (completeness_score + validity_score + consistency_score) / 3 >= 90 then 'B'
            when (completeness_score + validity_score + consistency_score) / 3 >= 80 then 'C'
            else 'D'
        end as data_quality_grade,

        -- The raw counts stay on the row so an analyst can see what drove the
        -- score without opening the model.
        blank_subcategory,
        blank_recommendation,
        blank_segment,
        rating_out_of_range,
        non_positive_order_total,
        cancelled_with_value,
        low_confidence_rating,
        order_predates_optimisation

    from scored

)

select * from final
order by data_quality_score asc

