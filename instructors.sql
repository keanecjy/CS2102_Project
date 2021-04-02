-- Helper function to generates the availability of that EID on that CURR_DATE with Session duration(span)
-- Assumption is start_time is in HOURS
-- Duration for all sessions are also in HOURS
-- Iterates from 9am to 6pm and checks if (Start_time, start + span) violates any constraints and populate the array
CREATE OR REPLACE FUNCTION check_availability(IN eid INT, IN span TIME, IN curr_date DATE)
    RETURNS TIME[] AS $$
DECLARE
    twelve_pm TIME := TIME '12:00';
    two_pm TIME := TIME '14:00';
    start_time TIME := TIME '09:00';
    end_time TIME := TIME '18:00';
    arr Time[] := ARRAY[]::Time[];
    one_hour interval := concat(1, ' hours')::interval;
BEGIN
    WHILE (start_time + span <= end_time) LOOP
            IF (1 == (SELECT 1 FROM Sessions S WHERE S.eid = eid AND S.session_date = curr_date
                                                 AND NOT (start_time, start_time + span) OVERLAPS (S.start_time - one_hour, S.end_time + one_hour)
                                                 AND NOT (start_time, start_time + span) OVERLAPS (twelve_pm, two_pm))) THEN
                arr = array_append(arr, start_time);
            END IF;
            start_time := start_time + one_hour;
        END LOOP;
    RETURN arr;
END;
$$ LANGUAGE plpgsql;




-- Helper function to get the total number of hours that EID have work in that month
CREATE OR REPLACE FUNCTION get_hours(IN _eid INT)
    RETURNS INT AS $$
DECLARE
    total_hour int;
BEGIN
    SELECT COALESCE(EXTRACT(HOUR FROM (
            SELECT SUM(end_time - start_time)
            FROM Sessions S 
            WHERE S.eid = _eid AND 
            (SELECT EXTRACT (MONTH FROM S.session_date)) = (SELECT EXTRACT(MONTH FROM CURRENT_DATE))
        )), 0) INTO total_hour;

    RETURN total_hour;
END;
$$ LANGUAGE plpgsql;





CREATE OR REPLACE FUNCTION find_instructors(IN cid int, IN session_date date, IN start_hour time)
    RETURNS TABLE (eid int, name text) AS $$
DECLARE
    span interval;
    end_hour time;
    max_hour interval := concat(30, ' hours')::interval;
    one_hour interval := concat(1, ' hours')::interval;
BEGIN
    -- validate session_date
    IF (SELECT EXTRACT(isodow FROM session_date) in (6, 7)) THEN
        RAISE EXCEPTION 'Session_date must be a weekday';
    END IF;

    -- validate start_hour
    IF (start_hour < TIME '09:00') THEN
        RAISE EXCEPTION 'Cant a session before 9am';
    END IF;

    SELECT concat(duration, ' hours')::interval INTO span FROM Courses WHERE Courses.course_id = cid;

    -- validate session_date + duration
    IF ((start_hour, start_hour + span) OVERLAPS (TIME '12:00', TIME '14:00') OR (start_hour + span > TIME '18:00')) THEN
        RAISE EXCEPTION 'Invalid start time! It might have overlapped with lunch time or end work timing';
    END IF;

    end_hour := start_hour + span;

    with
        R0 as (SELECT DISTINCT Q0.eid, Q0.name
               FROM ((SELECT * FROM Courses WHERE Courses.course_id = cid) AS TEMP1 NATURAL JOIN Specializes) AS Q0
        ),
        R1 AS (SELECT DISTINCT Q1.eid, Q1.name
               FROM (SELECT * FROM R0 NATURAL JOIN Part_time_instructors) AS Q1
               WHERE NOT EXISTS (
                       SELECT 1
                       FROM Sessions S1
                       WHERE S1.session_date = session_date
                         AND S1.eid = Q1.eid
                         AND ((start_hour, end_hour) OVERLAPS (S1.start_time - one_hour, S1.end_time + one_hour)
                           OR
                              (concat((SELECT get_hours(Q1.eid)), ' hours')::interval) + (end_hour - start_hour) > max_hour
                           )
                   )
        ),
        R2 AS (SELECT DISTINCT Q2.eid, Q2.name
               FROM (SELECT * FROM R0 NATURAL JOIN Full_time_instructors) AS Q2
               WHERE NOT EXISTS(
                       SELECT 1
                       FROM Sessions S1
                       WHERE S1.session_date = session_date
                         AND S1.eid = Q2.eid
                         AND (start_hour, end_hour) OVERLAPS (S1.start_time - one_hour, S1.end_time + one_hour)
                   )
        )
    SELECT * from R1 union SELECT * from R2;
END;
$$ LANGUAGE plpgsql;



-- R0 denotes employees who are specializes in that course area
-- R1 DENOTES {start_date, ..., end_date} each increment in per day
-- R2 Checks through the part_time_instructors and select those whose total hours + duration <= 30 and and the day which
-- Iterate though should only contain mon-fri and check if there is any availability for that day itself
-- R3 checks through the full time instructors and select those whos days are available.
CREATE OR REPLACE FUNCTION get_available_instructors(IN cid INT, IN start_date date, IN end_date date)
    RETURNS TABLE (eid INT, name TEXT, hours INT, day date, available_hours Time[]) AS $$
DECLARE
    max_hour interval;
    span interval;
BEGIN
    SELECT concat(duration, ' hours')::interval INTO span FROM Courses WHERE Courses.course_id = cid;
    max_hour := concat(30, ' hours')::interval;
    with
        R0 AS (SELECT DISTINCT Q0.eid, Q0.name
               FROM ((SELECT * FROM Courses WHERE Courses.course_id = cid) AS TEMP1 NATURAL JOIN Specializes) AS Q0
        ),
        R1 AS (SELECT s_day FROM generate_series(start_date, end_date, '1 day') AS S(s_day)),
        R2 AS (SELECT DISTINCT Q2.eid, Q2.name, (SELECT get_hours(Q2.eid)), Q2.s_day, (SELECT check_availability(Q2.eid, span, Q2.s_day))
               FROM (R0 NATURAL JOIN Part_time_instructors CROSS JOIN R1) AS Q2
               WHERE (concat((SELECT get_hours(Q2.eid)), ' hours')::interval) + span <= max_hour
                 AND (SELECT EXTRACT(dow FROM Q2.s_day) IN (1,2,3,4,5))
                 AND (array_length(check_availability(Q2.eid, span, Q2.s_day), 1)) <> 0
        ),
        R3 AS (SELECT DISTINCT Q3.eid, Q3.name, (SELECT get_hours(Q3.eid)), Q3.s_day, (SELECT check_availability(Q3.eid, span, Q3.s_day))
               FROM (R0 NATURAL JOIN Full_time_instructors CROSS JOIN R1) AS Q3
               WHERE (SELECT EXTRACT(dow FROM Q3.s_day) IN (1,2,3,4,5))
                 AND (array_length(check_availability(Q3.eid, span, Q3.s_day), 1)) <> 0
        )
    SELECT * FROM R2 union  SELECT * FROM R3 ORDER BY (R2.eid, R2.s_day); -- not sure if correct syntax
END;
$$ LANGUAGE plpgsql;



-- Do I need to consider propagating?
/*
 * Things to check:
 * 1) If session_date is later than current_date (Done)
 * 2) Check if on that day for the new EID, there is any overlaps with his old timing (in instructors_overlap_timing_checks)
 * 3) If part-time instructor, check that the sum of all his timing + new duration for this month <= 30 (in instructors_part_time_duration_checks)
 * 4) Check if instructor specializes in that course (in instructors_specialization_checks)
 */
CREATE OR REPLACE PROCEDURE update_instructor(cid INT, date_of_launch DATE, sid INT, new_eid INT)
AS $$
DECLARE
    s_date date; -- session date
BEGIN
    SELECT S.session_date into s_date FROM Sessions S WHERE S.sid = sid AND S.launch_date = date_of_launch AND S.cid = cid;
    IF (current_date < s_date) THEN
        RAISE EXCEPTION 'This session has already passed';
    END IF;

    UPDATE Sessions
    SET eid = new_eid
    WHERE eid = (SELECT S1.eid FROM Sessions S1 WHERE S1.course_id = cid AND S1.sid = sid AND S1.launch_date = date_of_launch);
END;
$$ LANGUAGE plpgsql;

	
	
