-- EMPLOYEES ATTENDANCE AUDIT REPORT
-- Purpose: Generates a CSV report first and last swipe of the day and counting working hours, searched by location and date/time range.

-- Set output to CSV format
.headers on
.mode csv
.output report.csv

-- Prepare raw swipe data with shift classification
WITH "swipe_data" AS (
    -- Output Columns: shift_group + comp_id from employee_profiles
    SELECT
        "swipes"."id",
        "swipes"."employee_id",
        "employee_profiles"."first_name" || ' ' || "employee_profiles"."last_name" AS "employee_name", -- Creating a full name in standard format
        "departments"."name" AS "department",
        "locations"."name" AS "location",
        "swipes"."swipe_time",
        "swipes"."access_granted",--
        CASE
            WHEN time("swipes"."swipe_time") >= '18:00:00'
                THEN date("swipes"."swipe_time", '+1 day') || 'N' -- Swipes after 18:00 → Assigned to the next day (e.g., 2023-01-01N)
            WHEN time("swipes"."swipe_time") < '07:00:00'
                THEN date("swipes"."swipe_time") || 'N'           -- Swipes before 07:00 → Assigned to the current day (e.g., 2023-01-01N)
            ELSE date("swipes"."swipe_time") || 'D'               -- All other swipes (e.g., 2023-01-01D)
        END AS "shift_group", "employee_profiles"."comp_id"
    FROM "swipes"
    -- Join employee, department, and location tables
    JOIN "employee_profiles"
        ON "swipes"."employee_id" = "employee_profiles"."id"
    JOIN "departments"
        ON "employee_profiles"."department_id" = "departments"."id"
    JOIN "locations"
        ON "employee_profiles"."location_id" = "locations"."id"
    -- Filter by location and date range (in this case Belgrade, RS for October 2023)
    WHERE "locations"."name" = 'Belgrade, RS'
        AND "swipes"."swipe_time" BETWEEN '2023-10-01 00:00:00' AND '2023-11-01 00:00:00'
),
-- Identify shift start/end times
"shift_boundaries" AS (
    --Output Colums: shift_type + comp_id
    SELECT
        "employee_id",
        "employee_name",
        "department",
        "location",
        "shift_group",
        MIN("swipe_time") AS "first_swipe", -- First swipe of the day
        MAX("swipe_time") AS "last_swipe",  -- Last swipe of the day
        CASE
            WHEN SUBSTR("shift_group", -1) = 'N' THEN 'Night Shift'
            ELSE 'Day Shift'                -- Derives shift_type from shift_group
        END AS "shift_type", "comp_id"
    FROM "swipe_data"
    WHERE "access_granted" = 1              -- Filters successful swipes
    GROUP BY "employee_id", "shift_group"
),
-- Fetch reader IDs for first/last swipes
"swipe_details" AS (
    -- Output Columns: All columns from shift_boundaries + first_reader_id, last_reader_id
    SELECT
        "shift_boundaries".*,
        -- Subqueries to retrieve reader_id for the exact first_swipe/last_swipe times
        (
            SELECT "swipes"."reader_id"
            FROM "swipes"
            WHERE "swipes"."employee_id" = "shift_boundaries"."employee_id"
                AND "swipes"."swipe_time" = "shift_boundaries"."first_swipe"
            LIMIT 1
        ) AS "first_reader_id",
        (
            SELECT "swipes"."reader_id"
            FROM "swipes"
            WHERE "swipes"."employee_id" = "shift_boundaries"."employee_id"
                AND "swipes"."swipe_time" = "shift_boundaries"."last_swipe"
            LIMIT 1
        ) AS "last_reader_id"
    FROM "shift_boundaries"
),
-- Calculate working hours
"shift_durations" AS (
    -- Output Columns: All columns from swipe_details + shift_date, adjusted_last_swipe, shift_hours
    SELECT
        "swipe_details".*,
        -- Extract shift_date from shift_group (e.g., 2023-01-01 from 2023-01-01N)
        DATE(SUBSTR("swipe_details"."shift_group", 1, 10)) AS "shift_date",
        -- Adjust last_swipe for night shifts
        CASE
            WHEN "shift_type" = 'Night Shift'
                THEN MIN(
                    "swipe_details"."last_swipe",
                    datetime(SUBSTR("swipe_details"."shift_group", 1, 10), '08:00:00') -- Caps end time at 08:00 AM of the next day
                )
            ELSE "swipe_details"."last_swipe"
        -- Computes shift_hours
        END AS "adjusted_last_swipe",
        ROUND(
            (
                JULIANDAY(
                    CASE
                        WHEN "shift_type" = 'Night Shift'
                            THEN MIN(
                                "swipe_details"."last_swipe",
                                datetime(SUBSTR("swipe_details"."shift_group", 1, 10), '08:00:00')
                            )
                        ELSE "swipe_details"."last_swipe"
                    END
                ) - JULIANDAY("swipe_details"."first_swipe")
            ) * 24, -- Duration in hours.
            2       --Rounded to 2 decimals
        ) AS "shift_hours"
    FROM "swipe_details"
)
-- Generate the report
-- Output Columns
SELECT
    "shift_durations"."employee_id",
    "shift_durations"."comp_id",
    "shift_durations"."employee_name",
    "shift_durations"."department",
    "shift_durations"."location",
    "shift_durations"."shift_date",
    "shift_durations"."first_swipe",
    "first_reader"."name" AS "first_reader_name",
    "shift_durations"."adjusted_last_swipe" AS "last_swipe",
    "last_reader"."name" AS "last_reader_name",
    "shift_durations"."shift_hours",
    "shift_durations"."shift_type"
FROM "shift_durations"
-- Join shift_durations with readers table to get reader names for first/last swipes
LEFT JOIN "readers" AS "first_reader"
    ON "shift_durations"."first_reader_id" = "first_reader"."id"
LEFT JOIN "readers" AS "last_reader"
    ON "shift_durations"."last_reader_id" = "last_reader"."id"
ORDER BY "shift_durations"."shift_date", "shift_durations"."employee_id"; -- Orders results by shift_date and employee_id
