CREATE OR REPLACE FUNCTION find_instructors(IN cid int, IN session_date date, IN start_hour time)
    RETURNS TABLE (eid int, name text) AS $$
    /* 
     * THERE MIGHT BE ISSUE WITH USING OVERLAP AS DOCUMENT STATE AT LEAST 1, SO 1 IS ACCEPTABLE
	 * NOT SURE IF WE ASSUME THE START_HOUR + DURATION DOESNT OVERLAP BETWEEN 12-2PM?
	 * START_HOUR >= 9?
	 * START_HOUR + DURATION <= 6?
     */
DECLARE
    span int;
    end_hour time;
    max_hour time;
BEGIN
    SELECT duration INTO span FROM Courses WHERE Courses.course_id = cid;
    end_hour := start_hour + concat(span, ' hours')::interval;
    start_hour := start_hour - concat(1, ' hours')::interval;
    end_hour := end_hour + concat(1, ' hours')::interval;
    max_hour := concat(30, ' hours')::interval;
    with
        R0 as (SELECT Q0.eid, Q0.name
               FROM
                   ((SELECT * FROM Courses WHERE Courses.course_id = cid) AS TEMP1
                       NATURAL JOIN
                       Specializes
                       NATURAL JOIN
                       Employees) AS Q0
        ),
        R1 AS (SELECT Q1.eid, Q1.name
               FROM (SELECT * FROM R0 NATURAL JOIN Part_time_instructors) AS Q1
               WHERE NOT EXISTS(
                       SELECT 1
                       FROM Sessions
                       WHERE Sessions.session_date = session_date
                         AND Sessions.eid = Q1.eid
                         AND (
                                   (start_hour, end_hour) OVERLAPS (Sessions.start_time, Sessions.end_time)
                               OR
                                   (SELECT EXTRACT(HOUR FROM
                                                   (SELECT SUM(start_time - end_time)
                                                    FROM Sessions
                                                    WHERE Sessions.course_id = cid AND Sessions.eid = Q1.eid
                                                   )
                                               )
                                   ) + (end_hour - start_hour) > max_hour
                           )
                   )
        ),
        R2 AS (SELECT Q2.eid, Q2.name
               FROM (SELECT * FROM R0 NATURAL JOIN Full_time_instructors) AS Q2
               WHERE NOT EXISTS(
                       SELECT 1
                       FROM Sessions
                       WHERE Sessions.session_date = session_date
                         AND Sessions.eid = Q2.eid
                         AND (start_hour, end_hour) OVERLAPS (Sessions.start_time, Sessions.end_time)
                   )
        )
    SELECT * from R1 union SELECT * from R2;
END;
$$ LANGUAGE plpgsql;

-- Assuming that each things is based on HOURS, we check per hour
-- Just iterating through from 9am to 6pm per hour and check if it overlaps with any timing that the EID already have
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
        IF (1 == (SELECT 1 FROM Sessions S
                  WHERE S.eid = eid AND S.session_date = curr_date
                    AND NOT (start_time, start_time + span) OVERLAPS (S.start_time - one_hour, S.end_time + one_hour)
                    AND NOT (start_time, start_time + span) OVERLAPS (twelve_pm, two_pm))) THEN
            arr = array_append(arr, start_time);
        END IF;
        start_time := start_time + one_hour;
    END LOOP;
    RETURN arr;
END;
$$ LANGUAGE plpgsql;

-- R0 denotes employees who are specializes in that course area
-- R1 DENOTES {start_date, ..., end_date} each increment in per day
-- R2 Checks through the part_time_instructors and select those whose total hours + duration <= 30 and and the day which
-- we iterate though should only contain mon-fri and check if there is any availability for that day itself
-- R3 checks trhough the full time instructors and select those whos days are available.
CREATE OR REPLACE FUNCTION get_available_instructors(IN cid INT, IN start_date date, IN end_date date)
    RETURNS TABLE (eid INT, name TEXT, hours INT, day date, available_hours Time[]) AS $$
DECLARE
    max_hour time;
    span time;
BEGIN
    SELECT concat(duration, ' hours')::interval INTO span FROM Courses WHERE Courses.course_id = cid;
    max_hour := concat(30, ' hours')::interval;
    with
        R0 AS (SELECT Q0.eid, Q0.name
               FROM
                   ((SELECT * FROM Courses WHERE Courses.course_id = cid) AS TEMP1
                       NATURAL JOIN
                       Specializes
                       NATURAL JOIN
                       Employees) AS Q0
        ),
        R1 AS (SELECT * FROM generate_series(start_date, end_date, '1 day')),
        R2 AS (SELECT Q2.eid, Q2.name, (SELECT EXTRACT(HOUR FROM
                                                       (SELECT SUM(start_time - end_time)
                                                        FROM Sessions
                                                        WHERE Sessions.eid = Q2.eid
                                                       )
                                                   )
        ), Q2.day, check_availability(Q2.eid, span, Q2.day)
               FROM (R0 NATURAL JOIN Part_time_instructors CROSS JOIN R1) AS Q2
               WHERE (SELECT EXTRACT(HOUR FROM
                                     (SELECT SUM(start_time - end_time)
                                      FROM Sessions
                                      WHERE Sessions.eid = Q2.eid
                                     )
                                 )
                     ) + span <= max_hour
                 AND (SELECT EXTRACT(dow FROM Q2.day) IN (1,2,3,4,5))
                 AND (array_length(check_availability(Q2.eid, span, Q2.day), 1)) <> 0
        ),
        R3 AS (SELECT Q3.eid, Q3.name, (SELECT EXTRACT(HOUR FROM
                                                       (SELECT SUM(start_time - end_time)
                                                        FROM Sessions
                                                        WHERE Sessions.eid = Q3.eid
                                                       )
                                                   )
        ), Q3.day, check_availability(Q3.eid, span, Q3.day)
               FROM (R0 NATURAL JOIN Full_time_instructors CROSS JOIN R1) AS Q3
               WHERE (SELECT EXTRACT(dow FROM Q3.day) IN (1,2,3,4,5))
                 AND (array_length(check_availability(Q3.eid, span, Q3.day), 1)) <> 0
        )
    SELECT * FROM R2 union  SELECT * FROM R3 ORDER BY (R2.eid, R2.day); -- not sure if correct syntax
END;
$$ LANGUAGE plpgsql;


	
	
	
	
	
	
	
	