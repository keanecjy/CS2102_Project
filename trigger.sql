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

/*
 * IF WANT EDIT REMEMBER TO DROP TRIGGERS
 */
-- TODO: Trigger - the assigned instructor must specialise in that course_area (CONSTRAINT TYPE) (Done)
/*
 * Constraint trigger on Sessions -> to enforce that the instructors teaching is specialized in that area
 */
CREATE OR REPLACE FUNCTION instructors_specialization_checks()
    RETURNS TRIGGER AS $$
DECLARE
    area text;
BEGIN
    SELECT DISTINCT area_name INTO area FROM Courses WHERE cid = NEW.course_id;

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


-- TODO: Trigger - each part-time instructor total hours per month <= 30 (CONSTRAINT TYPE) (Done)
/*
 * Constraint trigger on Sessions -> to enforce that if instructor is part time, the sum of his hour and this sessions for
 * this month is <= 30
 */
CREATE OR REPLACE FUNCTION instructors_part_time_duration_checks()
    RETURNS TRIGGER AS $$
DECLARE
    span TIME;
    max_hour time;
BEGIN
    SELECT DISTINCT duration INTO span FROM Courses WHERE cid = NEW.course_id;
    max_hour := concat(30, ' hours')::interval;

    -- VALIDATE PART-TIME INSTRUCTOR
    IF (NEW.eid IN (SELECT eid FROM Part_time_instructors) AND ((concat((SELECT get_hours(NEW.eid)), ' hours')) + span > max_hour)) THEN
        RAISE EXCEPTION 'This part-time instructor is going to be OVERWORKED if he take this session!';
        RETURN NULL;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER instructors_part_time_duration_checks
BEFORE INSERT OR UPDATE ON Sessions
FOR EACH ROW EXECUTE FUNCTION instructors_part_time_duration_checks();


-- TODO: Trigger - each instructor at most one course session at any hour (CONSTRAINT TYPE) (Done)
-- TODO: Trigger - each instructor must not teach 2 consecutive sessions (1 hr break) (CONSTRAINT TYPE) (Done)
/*
 * Constraint on Sessions -> To enforce that any instructors teaching, there isnt any overlap with any sessions
 * and there must be a 1hr break
 */
CREATE OR REPLACE FUNCTION instructors_overlap_timing_checks()
    RETURNS TRIGGER AS $$
DECLARE
    one_hour time;
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


-- TODO: Trigger - Each room can be used to conduct at most one course session at any time (CONSTRAINT TYPE) (Done)
/*
 * Constraint on Sessions -> To enforce if a room is taken, this sessions should not be added 
 */
CREATE OR REPLACE FUNCTION room_availability_checks()
    RETURNS TRIGGER AS $$
BEGIN
    -- VALIDATE THE ROOM AVAILABILITY
    IF (EXISTS (SELECT 1 FROM Sessions S WHERE S.session_date = NEW.session_date AND S.start_time = NEW.start_time AND S.rid = NEW.rid)) THEN
        RAISE EXCEPTION 'This room is already taken by another session';
        RETURN NULL;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER room_availability_checks
BEFORE INSERT ON Sessions
FOR EACH ROW EXECUTE FUNCTION room_availability_checks();


