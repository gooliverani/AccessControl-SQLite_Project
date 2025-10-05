-- ATTENDANCE AUDIT REPORT FOR SPECIFIC EMPLOYEE
-- Purpose: Generates a CSV report of all access attempts for employee 'JS100004'
--      during October 2023, with access validation and badge status checks

-- Identify target employee via comp_id
WITH "employee_data" AS (
    SELECT
        "id",
        "department_id",
        "location_id",
        "expire_date",
        "employment_type",
        "first_name" || ' ' || "last_name" AS "employee_name"
    FROM "employee_profiles"
    WHERE "comp_id" = 'JS100004'
),
-- Retrieve swipe records with access verification
"access_check" AS (
    SELECT
        "swipes"."id" AS "swipe_id",
        "swipes"."swipe_time",
        "swipes"."access_granted",
        "swipes"."employee_id",
        "swipes"."reader_id",
        "ea_sub"."employee_id" IS NOT NULL AS "has_access"
    FROM "swipes"
    -- Uses LEFT JOIN for access verification (NULL = no access)
    LEFT JOIN (
        SELECT "employee_access"."employee_id", "access_readers"."reader_id"
        FROM "employee_access"
        JOIN "access_readers" ON "employee_access"."access_id" = "access_readers"."access_id"
    ) AS "ea_sub"
        ON "swipes"."employee_id" = "ea_sub"."employee_id"
        AND "swipes"."reader_id" = "ea_sub"."reader_id"
    WHERE "swipes"."employee_id" IN (SELECT "id" FROM "employee_data")
      AND "swipes"."swipe_time" BETWEEN '2023-10-01 00:00:00' AND '2023-11-01 00:00:00' -- Retrieve all swipe records in October 2023
)
-- Verify access rights for each swipe attempt
SELECT
    "employee_data"."employee_name" AS "Employee",
    "access_check"."swipe_id",
    "access_check"."swipe_time" AS "Timestamp",
    "readers"."name" AS "Reader",
    "locations"."name" AS "Location",
    CASE "access_check"."access_granted" WHEN 1 THEN 'GRANTED' ELSE 'DENIED' END AS "Result",
    (
        SELECT GROUP_CONCAT("access"."name", ', ')  -- GROUP_CONCAT lists required access profiles
        FROM "access_readers"
        JOIN "access" ON "access_readers"."access_id" = "access"."id"
        WHERE "access_readers"."reader_id" = "access_check"."reader_id"
    ) AS "Required_Access_Profiles",
    -- Check badge validity during each access
    CASE WHEN "access_check"."has_access" THEN 'YES' ELSE 'NO' END AS "Had_Required_Access",
    CASE WHEN "employee_data"."expire_date" >= CAST(strftime('%Y%m%d', "access_check"."swipe_time") AS INTEGER)
        THEN 'VALID' ELSE 'EXPIRED' END AS "Badge_Status",
    "departments"."name" AS "Department",
    "employee_data"."employment_type" AS "Employment_Type"
FROM "access_check"
JOIN "employee_data" ON "access_check"."employee_id" = "employee_data"."id"
JOIN "readers" ON "access_check"."reader_id" = "readers"."id"
JOIN "locations" ON "readers"."location_id" = "locations"."id"
JOIN "departments" ON "employee_data"."department_id" = "departments"."id"
ORDER BY "access_check"."swipe_time" DESC;  -- Sort chronologically (newest first)
