/******************************************
 * BEFORE INSERT ON SESSIONS
 *****************************************/

CREATE OR REPLACE FUNCTION session_date_checks()
    RETURNS TRIGGER AS
$$
DECLARE
    course_deadline DATE;
    max_sid INT;
BEGIN
    SELECT DISTINCT registration_deadline INTO course_deadline
    FROM Offerings natural join Courses
    WHERE course_id = NEW.course_id
      AND launch_date = NEW.launch_date;

    IF (current_date > course_deadline) THEN
        RAISE EXCEPTION 'Course registration deadline have already PASSED!';
    END IF;

    -- check and enforce that the sid being inserted is in increasing order
    SELECT MAX(S.sid) INTO max_sid From Sessions S WHERE S.course_id = NEW.course_id AND S.launch_date = NEW.launch_date;
    IF (NEW.sid <= max_sid) THEN
        RAISE EXCEPTION 'Sid is not in increasing order';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER session_date_checks
    BEFORE INSERT ON Sessions
    FOR EACH ROW EXECUTE FUNCTION session_date_checks();

/******************************************
* BEFORE INSERT OR UPDATE ON SESSIONS
*****************************************/

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
CREATE OR REPLACE FUNCTION instructors_part_time_duration_checks()
    RETURNS TRIGGER AS $$
DECLARE
    span int;
BEGIN
    SELECT duration into span
    FROM Courses
    WHERE course_id = NEW.course_id;

    -- VALIDATE PART-TIME INSTRUCTOR
    IF (NEW.eid IN (SELECT eid FROM Part_time_instructors) AND ((SELECT get_hours(NEW.eid)) + span > 30)) THEN
        RAISE EXCEPTION 'This part-time instructor is going to be OVERWORKED if he take this session!';
        RETURN NULL;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS instructors_part_time_duration_checks on Sessions;

CREATE TRIGGER instructors_part_time_duration_checks
    BEFORE INSERT OR UPDATE ON Sessions
    FOR EACH ROW EXECUTE FUNCTION instructors_part_time_duration_checks();

CREATE OR REPLACE FUNCTION room_availability_checks()
    RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'UPDATE' AND OLD.rid = NEW.rid) THEN
        RETURN NEW;
    END IF;

    -- VALIDATE THE ROOM AVAILABILITY
    IF (EXISTS (SELECT 1
                FROM Sessions S
                WHERE S.session_date = NEW.session_date
                  AND S.rid = NEW.rid
                  AND (S.start_time, S.end_time) OVERLAPS (NEW.start_time, NEW.end_time)
        )
        ) THEN
        RAISE EXCEPTION 'Room % is already taken by another session', NEW.rid;
        RETURN NULL;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS room_availability_checks on Sessions;

CREATE TRIGGER room_availability_checks
    BEFORE INSERT OR UPDATE ON Sessions
    FOR EACH ROW EXECUTE FUNCTION room_availability_checks();

CREATE OR REPLACE FUNCTION new_session_timing_collision_checks()
    RETURNS TRIGGER AS $$
DECLARE
    twelve_pm TIME := TIME '12:00';
    two_pm TIME := TIME '14:00';
    start_time TIME := TIME '09:00';
    end_time TIME := TIME '18:00';
BEGIN
    IF (NEW.start_time < start_time OR NEW.end_time > end_time OR (NEW.start_time, NEW.end_time) OVERLAPS (twelve_pm, two_pm)) THEN
        RAISE EXCEPTION 'Invalid start time to end time for this Sessions. If might have overlap with lunch break or cuts into start or end time';
        RETURN NULL;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER new_session_timing_collision_checks
    BEFORE INSERT OR UPDATE ON Sessions
    FOR EACH ROW EXECUTE FUNCTION new_session_timing_collision_checks();

/******************************************
 * BEFORE DELETE ON SESSIONS
 *****************************************/

-- TODO: Trigger - Request must not be performed if there is at least one registration for the session
DROP TRIGGER IF EXISTS delete_session_checks on Sessions;

CREATE OR REPLACE FUNCTION delete_session_checks()
    RETURNS TRIGGER AS $$
DECLARE
    date_of_session DATE;
BEGIN

    -- checks if there is even this session to delete
    IF (NOT EXISTS (SELECT 1 FROM Sessions S WHERE S.course_id = OLD.course_id AND S.sid = OLD.sid AND S.launch_date = OLD.launch_date)) THEN
        RAISE EXCEPTION 'NO SUCH SESSION TO DELETE';
    END IF;
    
    -- checks if there is anyone who exist in registers who sign up for that particular course and that particular session
    IF (EXISTS (SELECT 1 FROM Registers WHERE sid = OLD.sid AND course_id = OLD.course_id AND launch_date = OLD.launch_date)
        OR EXISTS (SELECT 1 FROM Redeems WHERE sid = OLD.sid AND course_id = OLD.course_id AND launch_date = OLD.launch_date)) THEN
        RAISE EXCEPTION 'There is someone who registered for this session already';
        RETURN NULL;
    END IF;

    -- checks if the course session have already started
    SELECT DISTINCT S.session_date into date_of_session FROM Sessions S where S.sid = OLD.sid and S.course_id = OLD.course_id and S.launch_date = OLD.launch_date;
    IF (date_of_session <= current_date) THEN
        RAISE EXCEPTION 'Course session has already started';
    END IF;
    
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER delete_session_checks
    BEFORE DELETE ON Sessions
    FOR EACH ROW EXECUTE FUNCTION delete_session_checks();


/******************************************
* AFTER INSERT ON SESSIONS
*****************************************/

CREATE OR REPLACE FUNCTION update_offerings_when_session_added()
    RETURNS TRIGGER AS $$
DECLARE
    min_date DATE;
    max_date DATE;
BEGIN
    -- TODO: SHIFT INTO TRIGGERS
    -- find the maxs and min of the session_date from that particular offering
    SELECT min(session_date), max(session_date) INTO min_date, max_date
    FROM Sessions S
    WHERE S.course_id = NEW.course_id
      AND S.launch_date = NEW.launch_date;

    -- updates the start and end date of Offerings
    -- updates the seating_capacity in Offerings to sum of seating capacity of sessions
    UPDATE Offerings
    SET start_date = min_date,
        end_date = max_date,
        seating_capacity = (
            SELECT SUM(Q1.seating_capacity)
            FROM (Rooms NATURAL JOIN Sessions) AS Q1
            WHERE Q1.course_id = NEW.course_id
              AND Q1.launch_date = NEW.launch_date)
    WHERE course_id = NEW.course_id
      AND launch_date = NEW.launch_date;
END;
$$ LANGUAGE plpgsql;
    
/******************************************
* AFTER INSERT OR UPDATE ON SESSIONS
*****************************************/

CREATE OR REPLACE FUNCTION instructors_overlap_timing_checks()
    RETURNS TRIGGER AS $$
DECLARE
    one_hour interval := concat(1, ' hours')::interval;
BEGIN
    -- VALIDATE AT MOST ONE COURSE SESSION AT ANY HOUR AND NOT TEACH 2 CONSECUTIVE SESSIONS
    IF ( 1 < (
        SELECT count(*)
        FROM Sessions S
        WHERE S.session_date = NEW.session_date AND S.eid = NEW.eid AND (NEW.start_time, NEW.end_time) OVERLAPS (S.start_time - one_hour, S.end_time + one_hour))) THEN

        RAISE EXCEPTION 'This instructor is either teaching in this timing or he is having consecutive sessions!';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS instructors_overlap_timing_checks on Sessions;

CREATE CONSTRAINT TRIGGER instructors_overlap_timing_checks
    AFTER INSERT OR UPDATE ON Sessions
    FOR EACH ROW EXECUTE FUNCTION instructors_overlap_timing_checks();

/******************************************
 * AFTER DELETE ON SESSIONS
 *****************************************/

CREATE OR REPLACE FUNCTION after_delete_of_sessions()
    RETURNS TRIGGER AS
$$
BEGIN
    IF (EXISTS (SELECT 1 FROM Offerings WHERE launch_date = OLD.launch_date AND course_id = OLD.Course_id) AND
        (SELECT COUNT(*) FROM Sessions S WHERE S.launch_date = OLD.launch_date AND S.course_id = OLD.course_id) = 0) THEN
        RAISE EXCEPTION  'You cant delete this session as there will be no more session left for this offering: %', OLD.course_id;
    END IF;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER after_delete_of_sessions
    AFTER DELETE ON Sessions
    FOR EACH ROW EXECUTE FUNCTION after_delete_of_sessions();

CREATE OR REPLACE FUNCTION after_delete_of_session_to_update()
    RETURNS TRIGGER AS
$$
DECLARE
    date_of_session DATE;
    date_of_start DATE;
    date_of_end DATE;
    second_smallest_date DATE;
    second_largest_date DATE;
BEGIN
    -- updates the start and end date of offerings
    SELECT O.start_date, O.end_date INTO date_of_start, date_of_end
    FROM Offerings O
    WHERE course_id = OLD_course_id
      AND launch_date = OLD.launch_date;

    IF (date_of_session = date_of_start) THEN
        SELECT S.session_date into second_smallest_date
        FROM Sessions S
        WHERE S.launch_date = OLD.launch_date
          AND S.course_id = OLD.course_id
        ORDER BY S.session_date ASC
        LIMIT 1;

        UPDATE Offerings
        SET start_date = second_smallest_date
        WHERE launch_date = OLD.launch_date
          AND course_id = OLD.course_id;
    END IF;

    IF (date_of_session = date_of_end) THEN
        SELECT S.session_date into second_largest_date
        FROM Sessions S
        WHERE S.launch_date = OLD.launch_date
          AND S.course_id = OLD.course_id
        ORDER BY S.Session_date DESC
        LIMIT 1;

        UPDATE Offerings
        SET end_date = second_largest_date
        WHERE launch_date = OLD.launch_date
          AND course_id = OLD.course_id;
    END IF;

    -- updates the seating_capacity in offering.
    UPDATE Offerings
    SET seating_capacity = seating_capacity - (SELECT R.seating_capacity from Rooms R WHERE R.rid = OLD.rid)
    WHERE launch_date = OLD.launch_date
      AND course_id = OLD.course_id;
END;
$$ LANGUAGE plpgsql;






