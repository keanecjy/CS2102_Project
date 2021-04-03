/**
 * Constraint trigger on Credit_cards
 *  -> to enforce total participation, every customer have at least one card
 */

CREATE OR REPLACE FUNCTION at_least_one_card()
RETURNS TRIGGER AS $$
BEGIN
    IF (NOT EXISTS(SELECT 1 FROM Credit_cards WHERE cust_id = OLD.cust_id)
        AND EXISTS(SELECT 1 FROM Customers WHERE cust_id = OLD.cust_id)) THEN
        RAISE EXCEPTION 'Sorry, customer id % must have at least one credit card', OLD.cust_id;
    END IF;

    RETURN OLD;
END
$$ language plpgsql;


DROP TRIGGER IF EXISTS at_least_one_card on Credit_cards;

CREATE CONSTRAINT TRIGGER at_least_one_card AFTER DELETE OR UPDATE ON Credit_cards
FOR EACH ROW
EXECUTE FUNCTION at_least_one_card();



/**
 * Constraint trigger on Buys
 *  -> to enforce that each customer can have at most one active or partially active package
 */

CREATE OR REPLACE FUNCTION at_most_one_package()
RETURNS TRIGGER AS $$
DECLARE
    num_packages int;
BEGIN
    WITH Redemption_CTE as (
        SELECT * 
        FROM Redeems NATURAL JOIN Sessions
        WHERE cust_id = NEW.cust_id
    )
    SELECT COUNT(*) INTO num_packages
    FROM Buys B
    WHERE cust_id = NEW.cust_id AND
        (num_remaining_redemptions > 0 OR 
            EXISTS(SELECT 1
                FROM Redemption_CTE R
                WHERE R.buy_date = B.buy_date AND
                    R.cust_id = B.cust_id AND
                    R.package_id = B.package_id AND
                    current_date + 7 <= launch_date));

    IF (num_packages > 1) THEN
        RAISE EXCEPTION 'Customer % can only have at most one active or partially active package', NEW.cust_id;
    END IF;

    RETURN NEW;
END
$$ language plpgsql;


DROP TRIGGER IF EXISTS at_most_one_package on Buys;

CREATE CONSTRAINT TRIGGER at_most_one_package AFTER INSERT OR UPDATE ON Buys
FOR EACH ROW
EXECUTE FUNCTION at_most_one_package();


-- DROP TRIGGER instructors_specialization_checks on Sessions;
-- DROP TRIGGER instructors_part_time_duration_checks on Sessions;
-- DROP TRIGGER room_availability_checks on Sessions;
-- DROP TRIGGER instructors_overlap_timing_checks on Sessions;
-- DROP TRIGGER new_session_timing_collision_checks ON Sessions;
-- DROP TRIGGER course_offering_exists_checks ON Sessions;
-- DROP TRIGGER delete_session_checks ON Sessions;
-- DROP TRIGGER unique_session_per_course_redeem_checks on Redeems;
-- DROP TRIGGER unique_session_per_course_register_checks on Registers;

CREATE OR REPLACE FUNCTION instructors_specialization_checks()
    RETURNS TRIGGER AS $$
DECLARE
    area text;
BEGIN
    SELECT DISTINCT area_name INTO area
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
BEFORE INSERT OR UPDATE ON Sessions
FOR EACH ROW EXECUTE FUNCTION instructors_specialization_checks();


CREATE OR REPLACE FUNCTION instructors_part_time_duration_checks()
    RETURNS TRIGGER AS $$
DECLARE
    span interval;
    max_hour interval := concat(30, ' hours')::interval;
BEGIN
    SELECT DISTINCT concat(duration, ' hours')::interval INTO span
    FROM Courses
    WHERE course_id = NEW.course_id;

    -- VALIDATE PART-TIME INSTRUCTOR
    IF (NEW.eid IN (SELECT eid FROM Part_time_instructors) AND ((concat((SELECT get_hours(NEW.eid)), ' hours')::interval) + span > max_hour)) THEN
        RAISE EXCEPTION 'This part-time instructor is going to be OVERWORKED if he take this session!';
        RETURN NULL;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER instructors_part_time_duration_checks
BEFORE INSERT OR UPDATE ON Sessions
FOR EACH ROW EXECUTE FUNCTION instructors_part_time_duration_checks();



CREATE OR REPLACE FUNCTION instructors_overlap_timing_checks()
    RETURNS TRIGGER AS $$
DECLARE
    one_hour interval;
BEGIN
    one_hour := concat(1, ' hours')::interval;
    -- VALIDATE AT MOST ONE COURSE SESSION AT ANY HOUR AND NOT TEACH 2 CONSECUTIVE SESSIONS
    IF (EXISTS(SELECT 1 FROM Sessions S WHERE S.session_date = NEW.session_date AND S.eid = NEW.eid
                                          AND (NEW.start_time, NEW.end_time) OVERLAPS (S.start_time - one_hour, S.end_time + one_hour))) THEN
        RAISE EXCEPTION 'This instructor is either teaching in this timing or he is having consecutive sessions!';
        RETURN NULL;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER instructors_overlap_timing_checks
BEFORE INSERT OR UPDATE ON Sessions
FOR EACH ROW EXECUTE FUNCTION instructors_overlap_timing_checks();



CREATE OR REPLACE FUNCTION room_availability_checks()
    RETURNS TRIGGER AS $$
BEGIN
    -- VALIDATE THE ROOM AVAILABILITY
    IF (EXISTS (SELECT 1
                FROM Sessions S
                WHERE S.session_date = NEW.session_date
                  AND S.rid = NEW.rid
                  AND (S.start_time, S.end_time) OVERLAPS (NEW.start_time, NEW.end_time)
        )
        ) THEN
        RAISE EXCEPTION 'This room is already taken by another session';
        RETURN NULL;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

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

-- I might delete this as this should be checked by the database via foreign key???
CREATE OR REPLACE FUNCTION course_offering_exists_checks()
    RETURNS TRIGGER AS $$
BEGIN
    IF (NOT EXISTS (SELECT 1 FROM Offerings WHERE launch_date = NEW.launch_date AND course_id = NEW.course_id)) THEN
        RAISE EXCEPTION 'There is no such course offering to add sessions';
        RETURN NULL;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER course_offering_exists_checks
BEFORE INSERT OR UPDATE ON Sessions
FOR EACH ROW EXECUTE FUNCTION course_offering_exists_checks();

-- TODO: Trigger - Request must not be performed if there is at least one registration for the session
CREATE OR REPLACE FUNCTION delete_session_checks()
    RETURNS TRIGGER AS $$
BEGIN
    -- checks if there is anyone who exist in registers who sign up for that particular course and that particular session
    IF (EXISTS (SELECT 1 FROM Registers WHERE sid = OLD.sid AND course_id = OLD.course_id AND launch_date = OLD.launch_date)
        OR EXISTS (SELECT 1 FROM Redeems WHERE sid = OLD.sid AND course_id = OLD.course_id AND launch_date = OLD.launch_date)) THEN
        RAISE EXCEPTION 'There is someone who registered for this session already';
        RETURN NULL;
    END IF;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER delete_session_checks
BEFORE DELETE ON Sessions
FOR EACH ROW EXECUTE FUNCTION delete_session_checks();

-- HELPER FUNCTION FOR THE TRIGGERS ONLY
CREATE OR REPLACE FUNCTION is_not_unique_session_per_course(IN date_of_launch DATE, IN course_id INT, IN cus_id INT)
    RETURNS BOOLEAN AS $$
BEGIN
    RETURN (EXISTS (SELECT 1 FROM Registers R WHERE R.launch_date = date_of_launch AND R.course_id = course_id AND R.cust_id = cus_id)
        OR
            EXISTS (SELECT 1 FROM Redeems R WHERE R.launch_date = date_of_launch AND R.course_id = course_id AND R.cust_id = cus_id));
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION unique_session_per_course_register_checks()
    RETURNS TRIGGER AS $$
BEGIN
    IF ((SELECT is_not_unique_session_per_course(NEW.launch_date, NEW.course_id, NEW.cust_id))) THEN
        RAISE EXCEPTION 'You already have a registered session for this course';
        RETURN NULL;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER unique_session_per_course_register_checks
BEFORE INSERT ON Registers
FOR EACH ROW EXECUTE FUNCTION unique_session_per_course_register_checks();

CREATE OR REPLACE FUNCTION unique_session_per_course_redeem_checks()
    RETURNS TRIGGER AS $$
BEGIN
    IF ((SELECT is_not_unique_session_per_course(NEW.launch_date, NEW.course_id, NEW.cust_id))) THEN
        RAISE EXCEPTION 'You already have a registered session for this course';
        RETURN NULL;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER unique_session_per_course_redeem_checks
BEFORE INSERT ON Redeems
FOR EACH ROW EXECUTE FUNCTION unique_session_per_course_redeem_checks();


/*
Trigger to check for inserting/updating a registration/redemption of session.
1) Check if current_date have already past the session_date itself
2) Check if current_date have already past the registration_deadline
3) Check if number of registration + redeems <= seating_capacity

*/
create or replace function reg_redeem_check()
    returns trigger as
$$
DECLARE
    deadline date;
    s_date   date;
    seat_cap int;

BEGIN

    select registration_deadline
    into deadline
    from Offerings
    where launch_date = new.launch_date
      and course_id = new.course_id;

    select seating_capacity, session_date
    into seat_cap, s_date
    from Sessions natural join Rooms
    where new.sid = sid
      and new.launch_date = launch_date
      and new.course_id = course_id;

    -- Check if current_date have already past the session_date or registration deadline
    if (current_date > s_date or current_date > deadline) then
        raise notice 'It is too late to register for this session!';
        return null;
    end if;

    -- Check if there is enough slots in the session
    if (get_num_registration_for_session(new.sid, new.launch_date, new.course_id) >= seat_cap) then
        raise notice 'Session % with Course id: % and launch date: % is already full', new.sid, new.course_id, new.launch_date;
        return null;
    end if;

    return new;
END;

$$ language plpgsql;


drop trigger if exists valid_session on Redeems;
drop trigger if exists valid_session on Registers;

create trigger valid_session
    before insert or update
    on Redeems
    for each row
execute function reg_redeem_check();

create trigger valid_session
    before insert or update
    on Registers
    for each row
execute function reg_redeem_check();

