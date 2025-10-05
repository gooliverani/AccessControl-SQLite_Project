-- Represent departments in a company
CREATE TABLE "departments" (
    "id" INTEGER,
    "name" TEXT NOT NULL CHECK("name" IN (
        'HR', 'Finance', 'ITS', 'Sales', 'Support')),
    PRIMARY KEY("id")
);

-- Represent site locations in a company
CREATE TABLE "locations" (
    "id" INTEGER,
    "name" TEXT NOT NULL CHECK ("name" IN (
        'Belgrade, RS', 'Boston, MA', 'Jakarta, ID',
        'Melbourne, AU', 'Santiago, CL')),
    PRIMARY KEY("id")
);

-- Represent Logical Devices (Readers/Doors)
CREATE TABLE "readers" (
    "id" INTEGER,
    "location_id" INTEGER,
    "name" TEXT NOT NULL,
    FOREIGN KEY("location_id") REFERENCES "locations"("id"),
    PRIMARY KEY("id")
);

-- Create unique index for composite key
CREATE UNIQUE INDEX "idx_readers_id_location" ON "readers"("id", "location_id");

-- Represent clearance codes/access profiles
CREATE TABLE "access" (
    "id" INTEGER,
    "location_id" INTEGER,
    "reader_id" INTEGER,
    "name" TEXT NOT NULL UNIQUE,
    PRIMARY KEY("id"),
    FOREIGN KEY ("location_id") REFERENCES "locations"("id"),
    FOREIGN KEY ("reader_id") REFERENCES "readers"("id")
);

-- Create composite unique index to access table
CREATE UNIQUE INDEX "idx_access_id_location" ON "access"("id", "location_id");

-- Represent junction table between access profiles and readers
CREATE TABLE "access_readers" (
    "access_id" INTEGER,
    "reader_id" INTEGER,
    "location_id" INTEGER,
    PRIMARY KEY ("access_id", "reader_id"),
    FOREIGN KEY ("reader_id", "location_id")
        REFERENCES "readers"("id", "location_id")
        ON DELETE CASCADE,
    FOREIGN KEY ("access_id", "location_id")
        REFERENCES "access"("id", "location_id")
        ON DELETE CASCADE
);

-- Represent rules for access profiles
CREATE TABLE "access_rules" (
    "department_id" INTEGER,
    "location_id" INTEGER,
    "access_id" INTEGER,
    PRIMARY KEY("department_id", "location_id", "access_id"),
    FOREIGN KEY("department_id") REFERENCES "departments"("id") ON DELETE CASCADE,
    FOREIGN KEY("location_id") REFERENCES "locations"("id") ON DELETE CASCADE,
    FOREIGN KEY("access_id") REFERENCES "access"("id") ON DELETE CASCADE
);

-- Index for faster access rule lookups
CREATE INDEX "idx_access_rules_dept_loc" ON "access_rules" ("department_id", "location_id");

-- Represent employee badge profiles
CREATE TABLE "employee_profiles" (
    "id" INTEGER,
    "department_id" INTEGER,
    "location_id" INTEGER,
    "comp_id" TEXT NOT NULL UNIQUE,
    "first_name" TEXT NOT NULL,
    "last_name" TEXT NOT NULL,
    "employment_type" TEXT NOT NULL CHECK (
        "employment_type" IN ('Contractor', 'Employee')),
    "issue_date" INTEGER NOT NULL DEFAULT (strftime('%Y%m%d', 'now')),
    "expire_date" INTEGER NOT NULL CHECK (expire_date > issue_date),
    FOREIGN KEY("department_id") REFERENCES "departments"("id") ON DELETE CASCADE,
    FOREIGN KEY("location_id") REFERENCES "locations"("id") ON DELETE CASCADE,
    PRIMARY KEY("id")
);

-- Track assigned access profiles
CREATE TABLE "employee_access" (
    "employee_id" INTEGER,
    "access_id" INTEGER,
    "assigned_date" INTEGER DEFAULT (strftime('%Y%m%d', 'now')),
    PRIMARY KEY("employee_id", "access_id"),
    FOREIGN KEY("employee_id") REFERENCES "employee_profiles"("id") ON DELETE CASCADE,
    FOREIGN KEY("access_id") REFERENCES "access"("id") ON DELETE CASCADE
);

-- Index for expiration management
CREATE INDEX "idx_employee_expiration" ON "employee_profiles"("expire_date");

-- Swipe Records Table
CREATE TABLE "swipes" (
    "id" INTEGER,
    "employee_id" INTEGER,
    "reader_id" INTEGER,
    "swipe_time" NUMERIC NOT NULL DEFAULT CURRNUMERICENT_TIMESTAMP,
    "access_granted" INTEGER NOT NULL DEFAULT 0 CHECK("access_granted" IN (0, 1)),
    FOREIGN KEY("employee_id") REFERENCES "employee_profiles"("id") ON DELETE CASCADE,
    FOREIGN KEY("reader_id") REFERENCES "readers"("id") ON DELETE CASCADE,
    PRIMARY KEY("id")
);

-- Indexes for efficient swipe queries
CREATE INDEX "idx_swipes_employee" ON "swipes"("employee_id");
CREATE INDEX "idx_swipes_time" ON "swipes"("swipe_time");
CREATE INDEX "idx_swipes_reader" ON "swipes"("reader_id");

-- Trigger: Validate comp_id format
CREATE TRIGGER "validate_comp_id"
BEFORE INSERT ON "employee_profiles"
FOR EACH ROW
BEGIN
    SELECT RAISE(ABORT, 'Invalid comp_id format')
    WHERE NOT (
        length(NEW."comp_id") = 8 AND
        substr(NEW."comp_id", 1, 1) = upper(substr(NEW."first_name", 1, 1)) AND
        substr(NEW."comp_id", 2, 1) = upper(substr(NEW."last_name", 1, 1)) AND
        substr(NEW."comp_id", 3, 6) GLOB '[0-9][0-9][0-9][0-9][0-9][0-9]'
    );
END;

-- Trigger: Assign access on hire
CREATE TRIGGER "assign_access_on_hire"
AFTER INSERT ON "employee_profiles"
FOR EACH ROW
BEGIN
    INSERT INTO "employee_access" ("employee_id", "access_id")
    SELECT NEW."id", "access_rules"."access_id"
    FROM "access_rules"
    WHERE "access_rules"."department_id" = NEW."department_id"
      AND "access_rules"."location_id" = NEW."location_id";
END;

-- Trigger: Update comp_id on name change
CREATE TRIGGER "update_comp_id_on_name_change"
AFTER UPDATE OF "first_name", "last_name" ON "employee_profiles"
FOR EACH ROW
BEGIN
    UPDATE "employee_profiles"
    SET "comp_id" =
        upper(substr(NEW."first_name",1,1)) ||
        upper(substr(NEW."last_name",1,1)) ||
        substr(OLD."comp_id", 3)
    WHERE "id" = NEW."id";
END;

-- Current Employee Access Summary
-- Security Insight: Shows active employees with assigned access profiles, critical for access audits
CREATE VIEW "current_employee_access" AS
SELECT
    "employee_profiles"."id" AS "employee_id",
    "employee_profiles"."comp_id",
    "employee_profiles"."first_name" || ' ' || "employee_profiles"."last_name" AS "employee_name",
    "departments"."name" AS "department",
    "locations"."name" AS "location",
    COUNT("employee_access"."access_id") AS "total_access_profiles",
    GROUP_CONCAT("access"."name", ', ') AS "access_profiles"
FROM "employee_profiles"
JOIN "departments" ON "employee_profiles"."department_id" = "departments"."id"
JOIN "locations" ON "employee_profiles"."location_id" = "locations"."id"
LEFT JOIN "employee_access" ON "employee_profiles"."id" = "employee_access"."employee_id"
LEFT JOIN "access" ON "employee_access"."access_id" = "access"."id"
WHERE "employee_profiles"."expire_date" > CAST(strftime('%Y%m%d', 'now') AS INTEGER)
GROUP BY "employee_profiles"."id";
