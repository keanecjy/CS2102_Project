/*
add_course:
add_course_offering:
get_available_course_offerings:
get_available_course_sessions:
update_course_session:
promote_courses:
popular_courses:
*/

-- Adds a course into the courses table
CREATE OR REPLACE PROCEDURE add_course(course_title text, course_desc text, course_area text, duration integer) AS
$$
INSERT INTO Courses
VALUES (COALESCE((SELECT MAX(course_id) FROM Courses), 0) + 1, course_title, course_desc, course_area, duration);
$$ LANGUAGE sql;


-- /*
-- Check for
-- 1. Valid course offering
-- 2. Sufficient instructors to add all of sessions
-- - Use an array to keep track of all the new session_ids added. If one of the sessions fail to find an instructor,
-- we terminate
-- */
CREATE OR REPLACE PROCEDURE add_course_offering(cid int, l_date date, fees float, reg_deadline date,
                                                target_num int, admin_id int, sessions_arr text[][]) AS
$$

DECLARE
    temp                text[];
    course_area         text;
    course_duration     int;
    s_date              date;
    s_time              time;
    s_rid               int;
    seat_capacity       int;
    inst_eid            int;
    next_sid            int;
    earliest_start_date date;
    latest_end_date     date;

BEGIN
    -- 	Checking validity of course offering information
    IF (ARRAY_LENGTH(sessions_arr, 1) = 0) THEN
        RAISE EXCEPTION 'Course offering details are invalid';
    END IF;

    SELECT area_name, duration INTO course_area, course_duration FROM Courses WHERE course_id = cid;
    next_sid := 1;
    seat_capacity := 0;

    -- Temp insertion to allow adding of Sessions
    INSERT INTO Offerings VALUES (l_date, cid, reg_deadline, NULL, NULL, admin_id, 0, 0, fees);

    -- Adding each session in
    FOREACH temp slice 1 IN ARRAY sessions_arr
        LOOP
            s_date := temp[1]::date;
            s_time := temp[2]::time;
            s_rid := temp[3];

            IF (earliest_start_date IS NULL OR earliest_start_date > s_date)
            THEN
                earliest_start_date := s_date;
            END IF;

            IF (latest_end_date IS NULL OR latest_end_date < s_date)
            THEN
                latest_end_date := s_date;
            END IF;

            -- Find an eid from the list of available instructors (do we need to find the most optimal?)
            SELECT eid INTO inst_eid FROM find_instructors(cid, s_date, s_time) LIMIT 1;

            INSERT INTO Sessions
            VALUES (next_sid, l_date, cid, s_date, s_time, s_time + course_duration, s_rid, inst_eid);

            seat_capacity := seat_capacity + (SELECT seating_capacity FROM Rooms WHERE rid = s_rid);
            inst_eid := NULL;
            next_sid := next_sid + 1;

        END LOOP;

    if (seat_capacity < target_num) then
        raise exception 'Seat capacity must at least equal to the registrations.';
    END IF;

    -- Update the course offerings record after all sessions are inserted
    UPDATE Offerings
    SET start_date                  = earliest_start_date,
        end_date                    = latest_end_date,
        target_number_registrations = target_num,
        seating_capacity            = seat_capacity
    WHERE course_id = cid
      AND launch_date = l_date;

END;

$$ LANGUAGE plpgsql;



-- Helper function to create table containing all registers and redeems
CREATE OR REPLACE FUNCTION combine_reg_redeems()
    RETURNS table
            (
                cust_id       int,
                sid           int,
                launch_date   date,
                course_id     int,
                register_date date
            )
AS
$$

SELECT cust_id, sid, launch_date, course_id, register_date
FROM Registers
UNION
SELECT cust_id, sid, launch_date, course_id, redeem_date
FROM Redeems;

$$ LANGUAGE sql;

-- -- Helper function to query the num of registrations for the offering
-- create or replace function get_num_registration_for_offering(cid int, date_launch date)
--     returns int AS
-- $$
-- select count(*)
-- from combine_reg_redeems()
-- where launch_date = date_launch
--   and course_id = cid;
-- $$ language sql;


-- Helper function to query the num of registrations for the session
CREATE OR REPLACE FUNCTION get_num_registration_for_session(session_id int, date_launch date, cid int) RETURNS bigint AS
$$
SELECT COALESCE(COUNT(*), 1)
FROM combine_reg_redeems()
WHERE sid = session_id
  AND launch_date = date_launch
  AND course_id = cid;
$$ LANGUAGE sql;

-- Q15
-- Retrieves all course offerings that can be registered
-- Output is sorted in ascending order of registration deadline and course title.
-- Can be registered == seating_capacity - numRegistered > 0
CREATE OR REPLACE FUNCTION get_available_course_offerings()
    RETURNS table
            (
                title                 text,
                area_name             text,
                start_date            date,
                end_date              date,
                registration_deadline date,
                fees                  float,
                remaining_seats       bigint
            )
AS
$$
WITH NumRegistered AS (SELECT course_id, launch_date, COUNT(*) AS numReg
                       FROM combine_reg_redeems()
                       GROUP BY course_id, launch_date)

SELECT title, area_name, start_date, end_date, registration_deadline, fees, seating_capacity - COALESCE(numReg, 0)
FROM (Courses NATURAL JOIN Offerings)
         NATURAL LEFT JOIN NumRegistered
WHERE start_date >= CURRENT_DATE
  AND seating_capacity - COALESCE(numReg, 0) > 0;

$$ LANGUAGE sql;



-- Q16
-- Retrieve all the available sessions for a course offering that could be registered.
CREATE OR REPLACE FUNCTION get_available_course_sessions(cid int, date_of_launch date)
    RETURNS table
            (
                session_date    date,
                start_time      time,
                inst_name       text,
                remaining_seats bigint
            )
AS
$$
SELECT session_date, start_time, name, seating_capacity - get_num_registration_for_session(sid, date_of_launch, cid)
FROM (Sessions NATURAL JOIN Rooms)
         NATURAL JOIN Employees
WHERE course_id = cid
  AND launch_date = date_of_launch
  AND session_date >= CURRENT_DATE
  AND seating_capacity - get_num_registration_for_session(sid, date_of_launch, cid) > 0;

$$ LANGUAGE sql;



/*
Q19
1. Check for seat availability is done by trigger
2. Check if customers registered or redeemed for the session and update accordingly
3. Check for current_date before registration deadline

*/
CREATE OR REPLACE PROCEDURE update_course_session(customer_id int, cid int, date_launch date, new_sid int) AS
$$
BEGIN
    IF (EXISTS(
            SELECT 1 FROM Redeems WHERE cust_id = customer_id AND course_id = cid AND launch_date = date_launch)) THEN

        UPDATE Redeems
        SET sid         = new_sid,
            redeem_date = CURRENT_DATE
        WHERE cust_id = customer_id
          AND course_id = cid
          AND launch_date = date_launch;
    ELSE
        UPDATE Registers
        SET sid         = new_sid,
            redeem_date = CURRENT_DATE
        WHERE cust_id = customer_id
          AND course_id = cid
          AND launch_date = date_launch;
    END IF;
END;
$$ LANGUAGE plpgsql;


/*

Q26
1. Check for inactive customers
2. For each inactive customer, find:
	- Course area A, whereby at least one of the three most recent course offerings are in A
	- If customer has not registered for any course offerings, every course area is of interest.
*/
CREATE OR REPLACE FUNCTION promote_courses()
    RETURNS table
            (
                cust_id      int,
                cust_name    text,
                course_area  text,
                course_id    int,
                course_title text,
                launch_date  date,
                reg_deadline date,
                fees         float
            )
AS
$$
WITH InActiveCust AS (SELECT cust_id
                      FROM Customers
                               NATURAL JOIN combine_reg_redeems()
                      GROUP BY cust_id
                      HAVING MAX(register_date) + INTERVAL '5 months' < DATE_TRUNC('month', CURRENT_DATE)),
     CustWithNoOfferings AS (SELECT cust_id, name
                             FROM Customers
                             WHERE cust_id NOT IN (SELECT cust_id FROM combine_reg_redeems())),
     NumRegistered AS (SELECT course_id, launch_date, COUNT(*) AS numReg
                       FROM combine_reg_redeems()
                       GROUP BY course_id, launch_date),
     ValidOfferings AS (SELECT *
                        FROM (Offerings NATURAL LEFT JOIN NumRegistered)
                                 NATURAL JOIN Courses
                        WHERE registration_deadline >= CURRENT_DATE
                          AND seating_capacity - COALESCE(numReg, 0) > 0),
     Res AS (SELECT cust_id,
                    name,
                    area_name,
                    course_id,
                    title,
                    launch_date,
                    registration_deadline,
                    fees
             FROM (CustWithNoOfferings
                      NATURAL JOIN Customers),
                  ValidOfferings

             UNION

             SELECT cust_id,
                    (SELECT name FROM Customers WHERE cust_id = R4.cust_id),
                    area_name,
                    course_id,
                    title,
                    launch_date,
                    registration_deadline,
                    fees
             FROM InActiveCust R4,
                  ValidOfferings R5
             WHERE R5.area_name IN (SELECT area_name
                                    FROM Courses
                                             NATURAL JOIN combine_reg_redeems()
                                    WHERE cust_id = R4.cust_id
                                    ORDER BY register_date DESC
                                    LIMIT 3))

SELECT *
FROM Res
ORDER BY cust_id, registration_deadline

$$ LANGUAGE sql;



-- Q28
CREATE OR REPLACE FUNCTION popular_courses()
    RETURNS table
            (
                course_id                   int,
                course_title                text,
                course_area                 text,
                num_offerings               bigint,
                num_reg_for_latest_offering bigint
            )
AS
$$

WITH NumRegistered AS (SELECT course_id, launch_date, COUNT(*) AS numReg
                       FROM combine_reg_redeems()
                       GROUP BY course_id, launch_date),
     ValidOfferings AS (SELECT *
                        FROM (Offerings NATURAL JOIN NumRegistered)
                                 NATURAL JOIN Courses
                        WHERE (EXTRACT(YEAR FROM start_date)) = (EXTRACT(YEAR FROM CURRENT_DATE)))

SELECT DISTINCT course_id,
                title,
                area_name,
                (SELECT COUNT(*) FROM ValidOfferings WHERE course_id = V1.course_id),
                numReg
FROM ValidOfferings V1
WHERE (SELECT COUNT(*) FROM ValidOfferings WHERE course_id = V1.course_id) >= 2
  AND V1.start_date >= ALL (SELECT start_date FROM ValidOfferings WHERE course_id = V1.course_id)
  AND NOT EXISTS(SELECT 1
                 FROM ValidOfferings V2,
                      ValidOfferings V3
                 WHERE V2.course_id = V3.course_id
                   AND V2.course_id = V1.course_id
                   AND V2.start_date < V3.start_date
                   AND V2.numReg >= V3.numReg)
ORDER BY numReg DESC, course_id;

$$ LANGUAGE sql;
