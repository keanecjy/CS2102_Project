-- session_number is not generated by system
-- TODO: Trigger - to enforce total participation, every Offerings has >= 1 Sessions (CONSTRAINT TYPE) (PERSPECTIVE: OFFERINGS?)
-- TODO: Trigger - start date and end date of Offerings is updated to the earliest and latest session_date (UPDATE TYPE) (Done)
-- TODO: Trigger - update seating_capacity in Offerings to sum of seating capacities of sessions (UPDATE TYPE)  (Done)
-- TODO: Trigger - the assigned instructor must specialise in that course_area (CONSTRAINT TYPE) (Done) (in instructors_specialization_checks)
-- TODO: Trigger - each part-time instructor total hours per month <= 30 (CONSTRAINT TYPE) (Done) (in instructors_part_time_duration_checks)
-- TODO: Trigger - each instructor at most one course session at any hour (CONSTRAINT TYPE) (Done) (in instructors_overlap_timing_checks)
-- TODO: Trigger - each instructor must not teach 2 consecutive sessions (1 hr break) (CONSTRAINT TYPE) (Done) (in instructors_overlap_timing_checks)
-- TODO: Trigger - Each room can be used to conduct at most one course session at any time (CONSTRAINT TYPE) (Done) (in room_availability_checks)
-- TODO: Trigger - New sessions added should not collide with lunch time or start or end timing (IN new_session_timing_collision_checks)
-- TODO: Trigger - Course offering have to exist first before adding session (in course_offering_exists)
CREATE OR REPLACE PROCEDURE add_session(cid INT, date_of_launch DATE, session_number INT, session_date DATE, start_hour TIME, eid INT, rid INT)
AS $$
DECLARE
    course_deadline DATE;
    span TIME;
    min_date DATE;
    max_date DATE;
    max_sid INT;
BEGIN
    SELECT DISTINCT registration_deadline, duration INTO course_deadline, span
    FROM Offerings
    WHERE course_id = cid
      AND launch_date = date_of_launch;

    IF (current_date > course_deadline) THEN
        RAISE EXCEPTION 'Course registration deadline have already PASSED!';
    END IF;

    -- check and enforce that the sid being inserted is in increasing order
    SELECT MAX(sid) INTO max_sid From Sessions S WHERE S.cid = cid AND S.launch_date = date_of_launch;
    IF (session_number <= max_sid) THEN
        RAISE EXCEPTION 'Sid is not in increasing order';
    END IF;

    INSERT INTO Sessions VALUES (session_number, date_of_launch, cid, session_date, start_hour, start_hour + span, rid, eid);

    -- find the maxs and min of the session_date from that particular offering
    SELECT min(session_date), max(session_date) INTO min_date, max_date
    FROM Sessions S
    WHERE S.course_id = cid
      AND S.launch_date = date_of_launch;

    -- updates the start and end date of Offerings
    UPDATE Offerings
    SET start_date = min_date
    WHERE course_id = cid
      AND launch_date = date_of_launch;

    UPDATE Offerings
    SET end_date = max_date
    WHERE course_id = cid
      AND launch_date = date_of_launch;

    -- updates the seating_capacity in Offerings to sum of seating capacity of sessions
    UPDATE Offerings
    SET seating_capacity = (
        SELECT SUM(Q1.seating_capacity)
        FROM (Rooms NATURAL JOIN Sessions) AS Q1
        WHERE Q1.course_id = cid
          AND Q1.launch_date = date_of_launch)
    WHERE course_id = cid
      AND launch_date = date_of_launch;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE remove_session(cid INT, date_of_launch DATE, sid INT)
AS $$
DECLARE
    session_date DATE;
    room_id INT;
    start_date DATE;
    end_date DATE;
    second_smallest_date DATE;
    second_largest_date DATE;
BEGIN
    SELECT DISTINCT S.session_date into session_date FROM Session S where S.sid = sid and S.cid = cid and S.launch_date = date_of_launch;
    IF (session_date <= current_date) THEN
        RAISE EXCEPTION 'Course session has already started';
    END IF;

    IF (NOT EXISTS (SELECT 1 FROM Sessions S WHERE S.cid = cid AND S.sid = sid AND S.launch_date = date_of_launch)) THEN
        RAISE EXCEPTION 'NO SUCH SESSION TO DELETE';
    END IF;

    -- deletes
    DELETE FROM Sessions S
    WHERE S.cid = cid
      AND S.sid = sid
      AND S.launch_date = date_of_launch
    RETURNING S.rid INTO room_id;

    -- updates the start and end date of offerings
    SELECT O.start_date, O.end_date INTO start_date, end_date
    FROM Offerings
    WHERE course_id = cid
      AND launch_date = date_of_launch;

    IF (session_date = start_date) THEN
        SELECT S.session_date into second_smallest_date
        FROM Sessions S
        WHERE S.sid = sid
          AND S.launch_date = date_of_launch
          AND S.cid = cid
        ORDER BY S.session_date
        OFFSET 1
            LIMIT 1;

        UPDATE Offerings
        SET start_date = second_smallest_date
        WHERE launch_date = date_of_launch
          AND course_id = cid;
    END IF;

    IF (session_date = end_date) THEN
        SELECT S.session_date into second_largest_date
        FROM Sessions S
        WHERE S.sid = sid
          AND S.launch_date = date_of_launch
          AND S.cid = cid
        ORDER BY S.Session_date DESC
        OFFSET 1
            LIMIT 1;

        UPDATE Offerings
        SET end_date = second_largest_date
        WHERE launch_date = date_of_launch
          AND course_id = cid;
    END IF;

    -- updates the seating_capacity in offering.
    UPDATE Offerings
    SET seating_capacity = seating_capacity - (SELECT R.seating_capacity from Rooms R WHERE R.rid = room_id)
    WHERE launch_date = date_of_launch
      AND course_id = cid;
END;
$$ LANGUAGE plpgsql;