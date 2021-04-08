-- to ensure that course offerings will have >= 1
-- DROP TRIGGER instructors_specialization_checks on Sessions;
-- DROP TRIGGER instructors_part_time_duration_checks on Sessions;
-- DROP TRIGGER room_availability_checks on Sessions;
-- DROP TRIGGER instructors_overlap_timing_checks on Sessions;
-- DROP TRIGGER new_session_timing_collision_checks ON Sessions;
-- DROP TRIGGER course_offering_exists_checks ON Sessions;
-- DROP TRIGGER delete_session_checks ON Sessions;
-- DROP TRIGGER unique_session_per_course_redeem_checks on Redeems;
-- DROP TRIGGER unique_session_per_course_register_checks on Registers;


/******************************************
 * BEFORE INSERT ON SESSIONS
 *****************************************/

-- Check if added session is a future one and uses a valid sid
CREATE OR REPLACE FUNCTION session_date_checks()
    RETURNS TRIGGER AS
$$
DECLARE
    course_deadline DATE;
    max_sid         INT;
BEGIN
    SELECT DISTINCT registration_deadline
    INTO course_deadline
    FROM Offerings
             natural join Courses
    WHERE course_id = NEW.course_id
      AND launch_date = NEW.launch_date;

    IF (current_date > course_deadline) THEN
        RAISE EXCEPTION 'Course registration deadline have already PASSED!';
    END IF;

    -- check and enforce that the sid being inserted is in increasing order
    SELECT MAX(S.sid)
    INTO max_sid
    From Sessions S
    WHERE S.course_id = NEW.course_id AND S.launch_date = NEW.launch_date;
    IF (NEW.sid <= max_sid) THEN
        RAISE EXCEPTION 'Sid is not in increasing order';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER session_date_checks
    BEFORE INSERT
    ON Sessions
    FOR EACH ROW
EXECUTE FUNCTION session_date_checks();

/******************************************
* BEFORE INSERT OR UPDATE ON SESSIONS
*****************************************/


-- Check if session does not collide with lunch hours or exceed working hours
-- Check if session start and end time is equal to course duration
CREATE OR REPLACE FUNCTION new_session_timing_checks()
    RETURNS TRIGGER AS
$$
DECLARE
    twelve_pm    TIME := TIME '12:00';
    two_pm       TIME := TIME '14:00';
    opening_time TIME := TIME '09:00';
    closing_time TIME := TIME '18:00';
    span         INTERVAL;
BEGIN

    SELECT DISTINCT concat(duration, ' hours')::interval
    INTO span
    FROM Courses
    WHERE course_id = NEW.course_id;

    IF (NEW.start_time + span <> NEW.end_time) THEN
        RAISE EXCEPTION 'Invalid session hours. The session duration does not match with the specified Course duration';
    end if;

    IF (NEW.start_time < opening_time OR NEW.end_time > closing_time OR
        (NEW.start_time, NEW.end_time) OVERLAPS (twelve_pm, two_pm)) THEN
        RAISE EXCEPTION 'Invalid start time to end time for this Sessions. If might have overlap with lunch break or falls outside the working hours';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER new_session_timing_checks
    BEFORE INSERT OR UPDATE
    ON Sessions
    FOR EACH ROW
EXECUTE FUNCTION new_session_timing_checks();



-- Check if session's course area and instructor's specialisation matches
CREATE OR REPLACE FUNCTION instructors_specialization_checks()
    RETURNS TRIGGER AS
$$
DECLARE
    area text;
BEGIN
    SELECT DISTINCT area_name
    INTO area
    FROM Courses
    WHERE course_id = NEW.course_id;

    -- VALIDATE SPECIALIZATION
    IF (NEW.eid NOT IN (SELECT DISTINCT eid FROM Specializes WHERE area_name = area)) THEN
        RAISE EXCEPTION 'Instructor is not specializing in this course area';
        RETURN NULL;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER instructors_specialization_checks
    BEFORE INSERT OR UPDATE
    ON Sessions
    FOR EACH ROW
EXECUTE FUNCTION instructors_specialization_checks();

/******************************************
 * BEFORE DELETE OR UPDATE ON SESSIONS
 *****************************************/

/******************************************
* AFTER INSERT ON SESSIONS
*****************************************/

-- update start and end time and seating capacity of course offerings
CREATE OR REPLACE FUNCTION update_offerings_when_session_modified()
    RETURNS TRIGGER AS
$$
DECLARE
    min_date DATE;
    max_date DATE;
BEGIN

    IF (TG_OP in ('INSERT', 'UPDATE')) THEN
        -- find the max and min of the session_date from that particular offering
        SELECT min(session_date), max(session_date)
        INTO min_date, max_date
        FROM Sessions S
        WHERE S.course_id = NEW.course_id
          AND S.launch_date = NEW.launch_date;

        -- updates the start and end date of Offerings
        -- updates the seating_capacity in Offerings to sum of seating capacity of sessions
        UPDATE Offerings
        SET start_date       = min_date,
            end_date         = max_date,
            seating_capacity = (
                SELECT SUM(Q1.seating_capacity)
                FROM (Rooms NATURAL JOIN Sessions) AS Q1
                WHERE Q1.course_id = NEW.course_id
                  AND Q1.launch_date = NEW.launch_date)
        WHERE course_id = NEW.course_id
          AND launch_date = NEW.launch_date;
    END IF;


    IF (TG_OP in ('DELETE', 'UPDATE') AND
        EXISTS(SELECT 1 FROM Offerings WHERE (course_id, launch_date) = (OLD.course_id, OLD.launch_date))) THEN

        -- find the max and min of the session_date from that particular offering
        SELECT min(session_date), max(session_date)
        INTO min_date, max_date
        FROM Sessions S
        WHERE S.course_id = OLD.course_id
          AND S.launch_date = OLD.launch_date;

        -- updates the start and end date of Offerings
        -- updates the seating_capacity in Offerings to sum of seating capacity of sessions
        UPDATE Offerings
        SET start_date       = min_date,
            end_date         = max_date,
            seating_capacity = (
                SELECT SUM(Q1.seating_capacity)
                FROM (Rooms NATURAL JOIN Sessions) AS Q1
                WHERE Q1.course_id = OLD.course_id
                  AND Q1.launch_date = OLD.launch_date)
        WHERE course_id = OLD.course_id
          AND launch_date = OLD.launch_date;
    END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_offerings_when_session_modified
    AFTER INSERT OR UPDATE OR DELETE
    ON Sessions
    FOR EACH ROW
EXECUTE FUNCTION update_offerings_when_session_modified();

/******************************************
* AFTER INSERT OR UPDATE ON SESSIONS
*****************************************/

-- Check if rooms of the sessions does not collide
CREATE OR REPLACE FUNCTION room_availability_checks()
    RETURNS TRIGGER AS
$$
BEGIN
    -- VALIDATE THE ROOM AVAILABILITY
    IF (1 < (SELECT count(*)
             FROM Sessions S
             WHERE S.session_date = NEW.session_date
               AND S.rid = NEW.rid
               AND (S.start_time, S.end_time) OVERLAPS (NEW.start_time, NEW.end_time))
        ) THEN
        RAISE EXCEPTION 'Room % is already taken by another session', NEW.rid;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER room_availability_checks
    AFTER INSERT OR UPDATE
    ON Sessions
    FOR EACH ROW
EXECUTE FUNCTION room_availability_checks();



-- Check if instructor is teaching at most one session at any time period
-- Check that instructor have at least an hour break between sessions.
CREATE OR REPLACE FUNCTION instructors_overlap_timing_checks()
    RETURNS TRIGGER AS
$$
DECLARE
    one_hour interval := '1 hours'::interval;
BEGIN
    -- VALIDATE INSTRUCTOR TEACH AT MOST ONE COURSE SESSION AT ANY HOUR WITH AT LEAST ONE HOUR BREAK IN BETWEEN SESSIONS
    IF (1 < (
        SELECT count(*)
        FROM Sessions S
        WHERE S.session_date = NEW.session_date
          AND S.eid = NEW.eid
          AND (NEW.start_time, NEW.end_time) OVERLAPS (S.start_time - one_hour, S.end_time + one_hour))) THEN

        RAISE EXCEPTION 'Instructor % is either teaching in this time slot or he is having consecutive sessions without any break in between!', NEW.eid;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER instructors_overlap_timing_checks
    AFTER INSERT OR UPDATE
    ON Sessions DEFERRABLE
    FOR EACH ROW
EXECUTE FUNCTION instructors_overlap_timing_checks();



-- Check that part time instructors cannot teach more than 30h in a month
CREATE OR REPLACE FUNCTION instructors_part_time_duration_checks()
    RETURNS TRIGGER AS
$$
BEGIN
    -- VALIDATE PART-TIME INSTRUCTOR
    IF (NEW.eid IN (SELECT eid FROM Part_time_instructors) AND
        ((SELECT get_hours(NEW.eid, NEW.session_date)) > 30)) THEN
        RAISE EXCEPTION 'Part-time instructor % is going to be OVERWORKED if he take this session!', NEW.eid;
        RETURN NULL;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER instructors_part_time_duration_checks
    AFTER INSERT OR UPDATE
    ON Sessions DEFERRABLE
    FOR EACH ROW
EXECUTE FUNCTION instructors_part_time_duration_checks();



-- Check that instructor have not left the company
CREATE OR REPLACE FUNCTION instructor_not_departed_checks()
    RETURNS TRIGGER AS
$$
BEGIN
    IF (TG_OP = 'UPDATE' and NEW.eid = OLD.eid) THEN
        RETURN NULL;
    END IF;

    IF (is_departed(NEW.eid, NEW.session_date)) THEN
        RAISE EXCEPTION 'This instructor would have departed before this session and cant teach it anymore';
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER instructor_not_departed_checks
    AFTER INSERT OR UPDATE
    ON Sessions DEFERRABLE
    FOR EACH ROW
EXECUTE FUNCTION instructor_not_departed_checks();

/******************************************
 * AFTER DELETE ON SESSIONS
 *****************************************/

-- Check that the course offerings have at least one session.
CREATE OR REPLACE FUNCTION after_delete_of_sessions()
    RETURNS TRIGGER AS
$$
BEGIN
    IF (EXISTS(SELECT 1 FROM Offerings WHERE launch_date = OLD.launch_date AND course_id = OLD.Course_id) AND
        (SELECT COUNT(*) FROM Sessions S WHERE S.launch_date = OLD.launch_date AND S.course_id = OLD.course_id) =
        0) THEN
        RAISE EXCEPTION 'You cannot do this as there will be no more session left for course offering: %', OLD.course_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER after_delete_of_sessions
    AFTER DELETE OR UPDATE
    ON Sessions DEFERRABLE
    FOR EACH ROW
EXECUTE FUNCTION after_delete_of_sessions();

/******************************************
 * AFTER DELETE OR UPDATE ON SESSIONS
 *****************************************/

-- Trigger - Request must not be performed if there is at least one registration for the session
CREATE OR REPLACE FUNCTION delete_session_checks()
    RETURNS TRIGGER AS
$$
BEGIN
    IF (TG_OP = 'UPDATE' AND OLD.sid = NEW.sid AND OLD.course_id = new.course_id AND
        NEW.launch_date = OLD.launch_date) THEN
        RETURN NEW;
    END IF;
    -- checks if there is anyone who exist in registers/redeems who sign up for that particular course and that particular session
    IF (EXISTS(SELECT 1
               FROM Registers
               WHERE sid = OLD.sid AND course_id = OLD.course_id AND launch_date = OLD.launch_date)
        OR EXISTS(SELECT 1
                  FROM Redeems
                  WHERE sid = OLD.sid AND course_id = OLD.course_id AND launch_date = OLD.launch_date)) THEN
        RAISE EXCEPTION 'There is someone who registered for this session already';
        RETURN NULL;
    END IF;

    -- checks if the course session have already started

    IF (OLD.session_date < current_date OR (OLD.session_date = current_date AND OLD.start_time < current_time)) THEN
        RAISE EXCEPTION 'Course session has already started';
    END IF;

    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER delete_session_checks
    AFTER DELETE OR UPDATE
    ON Sessions DEFERRABLE
    FOR EACH ROW
EXECUTE FUNCTION delete_session_checks();