-- Helper function to generates the availability of that EID on that CURR_DATE with Session duration(span)
-- Assumption is start_time is in HOURS
-- Duration for all sessions are also in HOURS
-- Iterates from 9am to 6pm and checks if (Start_time, start + span) violates any constraints and populate the array
CREATE OR REPLACE FUNCTION check_availability(IN eid INT, IN span TIME, IN curr_date DATE)
    RETURNS TIME[] AS $$
DECLARE
    twelve_pm time;
    two_pm time;
    start_time time;
    end_time time;
    arr Time[] := ARRAY[]::Time[];
    one_hour time;
BEGIN
    one_hour := concat(1, ' hours')::interval;
    twelve_pm := TIME '12:00';
    two_pm := TIME '14:00';
    start_time := TIME '09:00';
    end_time := TIME '18:00';
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
CREATE OR REPLACE FUNCTION get_hours(IN eid INT)
    RETURNS INT AS $$
DECLARE
    total_hour int;
BEGIN
    SELECT EXTRACT(HOUR FROM (SELECT SUM(end_time - start_time)
                              FROM Sessions S where S.eid = eid
                                                AND (SELECT EXTRACT (MONTH FROM S.session_date)) = (SELECT EXTRACT(MONTH FROM CURRENT_DATE)))
               ) INTO total_hour;
    RETURN total_hour;
END;
$$ LANGUAGE plpgsql;





CREATE OR REPLACE FUNCTION find_instructors(IN cid int, IN session_date date, IN start_hour time)
    RETURNS TABLE (eid int, name text) AS $$
DECLARE
    span int;
    end_hour time;
    max_hour time;
    one_hour time;
BEGIN
    -- validate session_date
    IF (SELECT EXTRACT(isodow FROM session_date) in (6, 7)) THEN
        RAISE EXCEPTION 'Session_date must be a weekday';
    END IF;

    -- validate start_hour
    IF (start_hour < TIME '09:00') THEN
        RAISE EXCEPTION 'Cant a session before 9am';
    END IF;

    SELECT duration INTO span FROM Courses WHERE Courses.course_id = cid;

    -- validate session_date + duration
    IF ((start_hour, start_hour + span) OVERLAPS (TIME '12:00', TIME '14:00') OR (start_hour + span > TIME '18:00')) THEN
        RAISE EXCEPTION 'Invalid start time! It might have overlapped with lunch time or end work timing';
    END IF;

    one_hour := concat(1, ' hours')::interval;
    end_hour := start_hour + concat(span, ' hours')::interval;
    max_hour := concat(30, ' hours')::interval;
    with
        R0 as (SELECT DISTINCT Q0.eid, Q0.name
               FROM
                   ((SELECT * FROM Courses WHERE Courses.course_id = cid) AS TEMP1
                       NATURAL JOIN
                       Specializes
                       NATURAL JOIN
                       Employees) AS Q0
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
                              (concat((SELECT get_hours(Q1.eid)), ' hours')) + (end_hour - start_hour) > max_hour
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
    max_hour time;
    span time;
BEGIN
    SELECT concat(duration, ' hours')::interval INTO span FROM Courses WHERE Courses.course_id = cid;
    max_hour := concat(30, ' hours')::interval;
    with
        R0 AS (SELECT DISTINCT Q0.eid, Q0.name
               FROM
                   ((SELECT * FROM Courses WHERE Courses.course_id = cid) AS TEMP1
                       NATURAL JOIN
                       Specializes
                       NATURAL JOIN
                       Employees) AS Q0
        ),
        R1 AS (SELECT s_day FROM generate_series(start_date, end_date, '1 day') AS S(s_day)),
        R2 AS (SELECT DISTINCT Q2.eid, Q2.name, (SELECT get_hours(Q2.eid)), Q2.s_day, (SELECT check_availability(Q2.eid, span, Q2.s_day))
               FROM (R0 NATURAL JOIN Part_time_instructors CROSS JOIN R1) AS Q2
               WHERE (concat((SELECT get_hours(Q2.eid)), ' hours')) + span <= max_hour
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




-- might have to ignore different launch_date???
CREATE OR REPLACE FUNCTION update_instructor_trigger()
    RETURNS TRIGGER AS $$
DECLARE
    old_cid int;
    old_sid int;
    new_eid int;
    session_date date;
    start_hour time;
    duration time;
    max_hour time;
    one_hour time;
BEGIN
    one_hour := concat(1, ' hours')::interval;
    old_cid := OLD.cid;
    old_sid := OLD.sid;
    new_eid := NEW.eid;
    max_hour := concat(30, ' hours')::interval;
    SELECT S.session_date, S.start_time, (S.end_time - S.start_time) INTO session_date, start_hour, duration
    FROM Sessions S
    WHERE S.eid = OLD.eid
      AND S.sid = OLD.sid;
    /*
     * Things to check:
     * 1) If session_date is later than current_date
     * 2) Check if on that day for the new EID, there is any overlaps with his old timing
     * 3) Check whether if instructor is part-time or full-time instructor
     * 4) If part-time instructor, check that the sum of all his timing + new duration for this month <= 30
     */
    IF (current_date < session_date AND
        1 = (SELECT 1 FROM Sessions S2 WHERE S2.eid = eid AND S2.session_date = session_date
                                         AND NOT EXISTS (
                    SELECT 1 FROM Sessions S3 WHERE S3.eid = S2.eid AND S3.session_date = session_date
                                                AND (start_hour, start_hour + duration) OVERLAPS (S3.start_time - one_hour, S3.end_time + one_hour)))) THEN
        IF (1 = (SELECT 1 FROM Part_time_instructors PTI WHERE PTI.eid = eid)) THEN
            IF ((SELECT EXTRACT(HOUR FROM (SELECT SUM(end_time - start_time) FROM Sessions WHERE Sessions.eid = eid)))
                    + duration <= max_hour) THEN
                RETURN NEW;
            ELSE
                RETURN NULL;
            END IF;
        ELSE
            RETURN NEW;
        END IF;
    ELSE
        RETURN NULL;
    END IF;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER update_instructor_trigger on Sessions;

-- this is to ensure that we only run this trigger when there is a change of instructor eid
CREATE TRIGGER update_instructor_trigger
    BEFORE UPDATE ON Sessions
    FOR EACH ROW WHEN (NEW.eid IS NOT NULL) EXECUTE FUNCTION update_instructor_trigger();

-- Do I need to consider propagating?
CREATE OR REPLACE PROCEDURE update_instructor(cid INT, sid INT, new_eid INT)
AS $$
UPDATE Sessions
SET eid = new_eid
WHERE eid = (SELECT S1.eid FROM Sessions S1 WHERE S1.course_id = cid AND S1.sid = sid);
$$ LANGUAGE SQL;

	
	