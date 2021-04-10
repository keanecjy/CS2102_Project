/**************************************
 * HELPER FUNCTIONS
 **************************************/

-- Helper function to check if an employee have left the company
CREATE OR REPLACE FUNCTION is_departed(emp_id int, query_date date)
    RETURNS boolean AS
$$
BEGIN
    RETURN COALESCE((SELECT depart_date FROM Employees WHERE emp_id = eid) < query_date, FALSE);
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


-- Helper function used internally to get the current active card of a customer.
-- Raises exception if the customer is invalid or the active card is expired.
CREATE OR REPLACE FUNCTION get_active_card(cid int)
    RETURNS Credit_cards AS
$$
DECLARE
    active_card Credit_cards;
BEGIN
    IF NOT EXISTS(SELECT 1 FROM Customers WHERE cust_id = cid) THEN
        RAISE EXCEPTION 'Non-existent customer id %', cid;
        RETURN NULL;
    END IF;

    SELECT *
    INTO active_card
    FROM Credit_cards
    WHERE cust_id = cid
    ORDER BY from_date
        DESC
    LIMIT 1;

    IF NOT found THEN
        RAISE EXCEPTION 'Internal error: No credit card found for customer id %', cid
            USING HINT = 'Please add a new credit card';

        RETURN NULL;
    ELSIF (active_card.expiry_date < CURRENT_DATE) THEN
        RAISE EXCEPTION 'Credit card for customer % expired', cid;

        RETURN NULL;
    END IF;

    RETURN active_card;
END
$$ LANGUAGE plpgsql;


-- Helper function to query the num of registrations for the session
CREATE OR REPLACE FUNCTION get_num_registration_for_session(session_id int, date_launch date, cid int) RETURNS bigint AS
$$
SELECT COALESCE(COUNT(*), 0)
FROM combine_reg_redeems()
WHERE sid = session_id
  AND launch_date = date_launch
  AND course_id = cid;
$$ LANGUAGE sql;


-- Helper function to generates the availability of that EID on that CURR_DATE with Session duration(span)
-- Assumption is start_time is in HOURS
-- Duration for all sessions are also in HOURS
-- Iterates from 9am to 6pm and checks if (Start_time, start + span) violates any constraints and populate the array
CREATE OR REPLACE FUNCTION check_availability(IN in_eid INT, IN span int, IN curr_date DATE)
    RETURNS TIME[] AS
$$
DECLARE
    twelve_pm     TIME     := TIME '12:00';
    two_pm        TIME     := TIME '14:00';
    _start_time   TIME     := TIME '09:00';
    _end_time     TIME     := TIME '18:00';
    arr           Time[]   := ARRAY []::Time[];
    one_hour      interval := CONCAT(1, ' hours')::interval;
    span_interval interval := CONCAT(span, ' hours')::interval;
BEGIN
    -- IF THIS GUY HAVE SOMETHING ON THIS DAY, THEN WE ITERATE, ELSE, WE CAN ADD ALL THE DAYS POSSIBLE
    IF (EXISTS(SELECT 1 FROM Sessions S WHERE S.eid = in_eid AND S.session_date = curr_date)) THEN
        WHILE (_start_time + span_interval <= _end_time)
            LOOP
                IF (NOT (_start_time, _start_time + span_interval) OVERLAPS (twelve_pm, two_pm)
                    AND NOT EXISTS(SELECT 1
                                   FROM Sessions S
                                   WHERE S.eid = in_eid
                                     AND S.session_date = curr_date
                                     AND (_start_time, _start_time + span_interval) OVERLAPS
                                         (S.start_time - one_hour, S.end_time + one_hour))) THEN
                    arr := ARRAY_APPEND(arr, _start_time);
                END IF;
                _start_time := _start_time + one_hour;
            END LOOP;
    ELSE
        WHILE (_start_time + span_interval <= _end_time)
            LOOP
                IF (NOT (_start_time, _start_time + span_interval) OVERLAPS (twelve_pm, two_pm)) THEN
                    arr = ARRAY_APPEND(arr, _start_time);
                END IF;
                _start_time := _start_time + one_hour;
            END LOOP;
    END IF;
    RETURN arr;
END;
$$ LANGUAGE plpgsql;


-- Helper function to get the total number of hours that EID have work in that month
CREATE OR REPLACE FUNCTION get_hours(IN in_eid INT, IN date_current DATE)
    RETURNS INT AS
$$
DECLARE
    total_hour int;
BEGIN
    SELECT COALESCE(EXTRACT(HOUR FROM (
        SELECT SUM(end_time - start_time)
        FROM Sessions S
        WHERE S.eid = in_eid
          AND (SELECT EXTRACT(MONTH FROM S.session_date)) = (SELECT EXTRACT(MONTH FROM date_current))
          AND (SELECT EXTRACT(YEAR FROM S.session_date)) = (SELECT EXTRACT(YEAR FROM date_current))
    )), 0)
    INTO total_hour;

    RETURN total_hour;
END;
$$ LANGUAGE plpgsql;


/**************************************
 * TRIGGERS
 **************************************/

-- TRIGGERS ON EMPLOYEES

-- Constraint trigger on Employees after insertion
--     -> to enforce that an employee must be a part-time or full-time employee
--     -> to enforce that an employee is either an instructor, administrator or manager
CREATE OR REPLACE FUNCTION insert_employee_cat_check()
    RETURNS TRIGGER AS
$$
DECLARE
    emp_count      int; -- count occurrence of employee in Part_time_emp and Full_time_emp
    emp_type_count int; -- count occurrence of employee in Instructors, Administrators and Managers
BEGIN
    emp_count := 0;
    emp_type_count := 0;

    -- check emp_count
    IF new.eid IN (SELECT eid FROM Part_time_emp) THEN
        emp_count := emp_count + 1;
    END IF;

    IF new.eid IN (SELECT eid FROM Full_time_emp) THEN
        emp_count := emp_count + 1;
    END IF;

    IF emp_count <> 1 THEN
        RAISE EXCEPTION 'Employee % must be in either Part_time_emp or Full_time_emp table.', new.eid;
    END IF;

    -- check emp_type_count
    IF new.eid IN (SELECT eid FROM Instructors) THEN
        emp_type_count := emp_type_count + 1;
    END IF;

    IF new.eid IN (SELECT eid FROM Administrators) THEN
        emp_type_count := emp_type_count + 1;
    END IF;

    IF new.eid IN (SELECT eid FROM Managers) THEN
        emp_type_count := emp_type_count + 1;
    END IF;

    IF emp_type_count <> 1 THEN
        RAISE EXCEPTION 'Employee % must be in either Instructors, Administrators or Managers table.', new.eid;
    END IF;

    RETURN new;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER insert_employee_cat_check
    AFTER INSERT OR UPDATE
    ON Employees DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
EXECUTE FUNCTION insert_employee_cat_check();



-- Constraint trigger on Part_time_instructors, Full_time_instructors,
-- Administrators and Managers after update or delete
-- -> to enforce that the old employee before update or delete is NOT in:
--    1) Employees table AND
--    2) either Part_time_emp or Full_time_emp table AND
--    3) Instructors table if old employee is a part-time or full-time instructor
--
-- NOTE: updating or deleting from Part_time_emp, Full_time_emp and Instructors
-- are not checked as:
-- 1) there will be a violation of foreign key constraint if there is a referenced tuple
--    in either Part_time_instructors, Full_time_instructors, Administrators or Managers
-- 2) any update or delete from  Part_time_instructors, Full_time_instructors, Administrators
--    or Managers must also be updated / deleted in its referencing tables
CREATE OR REPLACE FUNCTION update_or_delete_employee_cat_check()
    RETURNS TRIGGER AS
$$
BEGIN
    -- If there is no change to eid, ignore the constraint check
    IF (TG_OP = 'UPDATE' AND OLD.eid = NEW.eid) THEN
        RETURN NULL;
    END IF;

    IF TG_TABLE_NAME = 'part_time_instructors' THEN
        IF old.eid IN (SELECT eid FROM Instructors) OR
           old.eid IN (SELECT eid FROM Part_time_emp) OR
           old.eid IN (SELECT eid FROM Employees) THEN
            RAISE EXCEPTION 'Part-time instructor % still exists in referenced tables.', old.eid;
        END IF;
        RETURN NULL;
    ELSIF TG_TABLE_NAME = 'full_time_instructors' THEN
        IF old.eid IN (SELECT eid FROM Instructors) OR
           old.eid IN (SELECT eid FROM Full_time_emp) OR
           old.eid IN (SELECT eid FROM Employees) THEN
            RAISE EXCEPTION 'Full-time instructor % still exists in referenced tables.', old.eid;
        END IF;
        RETURN NULL;
    ELSIF TG_TABLE_NAME = 'administrators' THEN
        IF old.eid IN (SELECT eid FROM Full_time_emp) OR
           old.eid IN (SELECT eid FROM Employees) THEN
            RAISE EXCEPTION 'Administrator % still exists in referenced tables.', old.eid;
        END IF;

        RETURN NULL;
    ELSIF TG_TABLE_NAME = 'managers' THEN
        IF old.eid IN (SELECT eid FROM Full_time_emp) OR
           old.eid IN (SELECT eid FROM Employees) THEN
            RAISE EXCEPTION 'Manager % still exists in referenced tables.', old.eid;
        END IF;

        RETURN NULL;
    ELSE
        RAISE EXCEPTION 'Internal error in update_or_delete_employee_cat_check';
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER update_or_delete_employee_cat_check
    AFTER UPDATE OR DELETE
    ON Part_time_instructors DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
EXECUTE FUNCTION update_or_delete_employee_cat_check();

CREATE CONSTRAINT TRIGGER update_or_delete_employee_cat_check
    AFTER UPDATE OR DELETE
    ON Full_time_instructors DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
EXECUTE FUNCTION update_or_delete_employee_cat_check();

CREATE CONSTRAINT TRIGGER update_or_delete_employee_cat_check
    AFTER UPDATE OR DELETE
    ON Administrators DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
EXECUTE FUNCTION update_or_delete_employee_cat_check();

CREATE CONSTRAINT TRIGGER update_or_delete_employee_cat_check
    AFTER UPDATE OR DELETE
    ON Managers DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
EXECUTE FUNCTION update_or_delete_employee_cat_check();



-- Constraint trigger on Part_time_emp
--    -> to enforce covering that all part-time employee is a part-time instructor
CREATE OR REPLACE FUNCTION part_time_emp_check()
    RETURNS TRIGGER AS
$$
BEGIN
    IF new.eid NOT IN (SELECT eid FROM Part_time_instructors) THEN
        RAISE EXCEPTION 'Part-time employee % must be in Part_time_instructors table.', new.eid;
    END IF;

    RETURN new;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER part_time_emp_check
    AFTER INSERT OR UPDATE
    ON Part_time_emp DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
EXECUTE FUNCTION part_time_emp_check();



-- To enforce all full-time employee is either a full-time instructor, administrator or manager
CREATE OR REPLACE FUNCTION full_time_emp_check()
    RETURNS TRIGGER AS
$$
DECLARE
    full_time_count int; -- count occurrence of full-time employee in Full_time_instructors, Administrators and Managers
BEGIN
    full_time_count := 0;

    IF new.eid IN (SELECT eid FROM Full_time_instructors) THEN
        full_time_count := full_time_count + 1;
    END IF;

    IF new.eid IN (SELECT eid FROM Administrators) THEN
        full_time_count := full_time_count + 1;
    END IF;

    IF new.eid IN (SELECT eid FROM Managers) THEN
        full_time_count := full_time_count + 1;
    END IF;

    IF full_time_count <> 1 THEN
        RAISE EXCEPTION 'Full-time employee % must be in either Full_time_instructors, Administrators or Managers table.', new.eid;
    END IF;

    RETURN new;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER full_time_emp_check
    AFTER INSERT OR UPDATE
    ON Full_time_emp DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
EXECUTE FUNCTION full_time_emp_check();



-- to enforce that an instructor is either a part-time or full-time instructor
CREATE OR REPLACE FUNCTION instructor_check()
    RETURNS TRIGGER AS
$$
DECLARE
    inst_count int;
BEGIN
    inst_count := 0;

    IF new.eid IN (SELECT eid FROM Part_time_instructors) THEN
        inst_count := inst_count + 1;
    END IF;

    IF new.eid IN (SELECT eid FROM Full_time_instructors) THEN
        inst_count := inst_count + 1;
    END IF;

    IF inst_count <> 1 THEN
        RAISE EXCEPTION 'Instructor % must be in either Part_time_instructors or Full_time_instructors table.', new.eid;
    END IF;

    RETURN new;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER instructor_check
    AFTER INSERT OR UPDATE
    ON Instructors DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
EXECUTE FUNCTION instructor_check();



-- to enforce a valid update of an employee's departure date
-- condition for validity is from function 2 (remove_employee)
CREATE OR REPLACE FUNCTION update_employee_departure()
    RETURNS TRIGGER AS
$$
BEGIN
    -- If employee already departed, ignore the constraint check
    IF (TG_OP = 'UPDATE' AND OLD.depart_date <= NEW.depart_date) THEN
        RETURN new;
    END IF;

    -- condition 1
    IF new.eid IN (SELECT eid FROM Administrators)
        AND new.depart_date < ANY (
            SELECT registration_deadline
            FROM Offerings
            WHERE eid = new.eid) THEN
        RAISE WARNING 'Departure date for employee id % is not updated as the administrator is handling some course offering where its registration deadline is after the departure date.', new.eid;
        RETURN NULL;
        -- condition 2
    ELSIF new.eid IN (SELECT eid FROM Instructors)
        AND new.depart_date < ANY (
            SELECT session_date
            FROM Sessions
            WHERE eid = new.eid) THEN
        RAISE WARNING 'Departure date for employee id % is not updated as the instructor is teaching some course session that starts after the departure date.', new.eid;
        RETURN NULL;
        -- condition 3
    ELSIF new.eid IN (SELECT eid FROM Managers)
        AND new.eid IN (SELECT eid FROM Course_areas) THEN
        RAISE WARNING 'Departure date for employee id % is not updated as the manager is still managing some course area.', new.eid;
        RETURN NULL;
    ELSE
        RETURN new;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_employee_departure
    BEFORE INSERT OR UPDATE
    ON Employees
    FOR EACH ROW
    WHEN (new.depart_date IS NOT NULL)
EXECUTE FUNCTION update_employee_departure();



-- to enforce that every instructor has >= 1 specialization
CREATE OR REPLACE FUNCTION at_least_one_specialization()
    RETURNS TRIGGER AS
$$
BEGIN
    IF TG_TABLE_NAME = 'instructors' THEN
        IF (new.eid NOT IN (SELECT eid FROM Specializes)) THEN
            RAISE EXCEPTION 'Instructor % must specialise in at least one course area.', new.eid;
        END IF;
    ELSE
        IF old.eid IN (SELECT eid FROM Instructors) AND
           old.eid NOT IN (SELECT eid FROM Specializes) THEN
            RAISE EXCEPTION 'Instructor % must specialise in at least one course area.', old.eid;
        END IF;
    END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER at_least_one_specialization
    AFTER INSERT OR UPDATE
    ON Instructors DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
EXECUTE FUNCTION at_least_one_specialization();

CREATE CONSTRAINT TRIGGER at_least_one_specialization
    AFTER UPDATE OR DELETE
    ON Specializes DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
EXECUTE FUNCTION at_least_one_specialization();


-- TRIGGERS ON CUSTOMERS


-- to enforce total participation, every customer have at least one card
CREATE OR REPLACE FUNCTION at_least_one_card()
    RETURNS TRIGGER AS
$$
DECLARE
    rec RECORD;
BEGIN
    IF TG_TABLE_NAME = 'customers' THEN
        rec = NEW;
    ELSIF TG_TABLE_NAME = 'credit_cards' THEN
        rec = OLD;
    END IF;

    IF (NOT EXISTS(SELECT 1 FROM Credit_cards WHERE cust_id = rec.cust_id)
        AND EXISTS(SELECT 1 FROM Customers WHERE cust_id = rec.cust_id)) THEN
        RAISE EXCEPTION 'Sorry, customer id % must have at least one credit card', rec.cust_id;
    END IF;

    RETURN rec;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER at_least_one_card
    AFTER INSERT OR UPDATE
    ON Customers DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
EXECUTE FUNCTION at_least_one_card();

CREATE CONSTRAINT TRIGGER at_least_one_card
    AFTER DELETE OR UPDATE
    ON Credit_cards DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
EXECUTE FUNCTION at_least_one_card();



-- Enforce that each customer can have at most one active or partially active package
CREATE OR REPLACE FUNCTION at_most_one_package()
    RETURNS TRIGGER AS
$$
DECLARE
    num_packages int;
BEGIN

    SELECT COUNT(*)
    INTO num_packages
    FROM Buys B
    WHERE cust_id = NEW.cust_id
      AND (num_remaining_redemptions > 0 OR
           EXISTS(SELECT 1
                  FROM Redeems R
                           NATURAL JOIN Sessions S
                  WHERE R.buy_date = B.buy_date
                    AND R.cust_id = B.cust_id
                    AND R.package_id = B.package_id
                    AND CURRENT_DATE + 7 <= S.session_date));

    IF (num_packages > 1) THEN
        RAISE EXCEPTION 'Customer % can only have at most one active or partially active package', NEW.cust_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER at_most_one_package
    AFTER INSERT OR UPDATE
    ON Buys DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
EXECUTE FUNCTION at_most_one_package();



-- Check if package is available using the buy_date
CREATE OR REPLACE FUNCTION check_valid_package()
    RETURNS TRIGGER AS
$$
BEGIN

    IF (NOT EXISTS(
            SELECT 1
            FROM Course_packages
            WHERE NEW.buy_date BETWEEN sale_start_date AND sale_end_date
              AND NEW.package_id = package_id)
        ) THEN

        RAISE EXCEPTION 'Course package % is not available', NEW.package_id
            USING HINT = 'Check for available courses using get_available_course_packages()';
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER check_valid_package
    AFTER INSERT OR UPDATE
    ON Buys DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
EXECUTE FUNCTION check_valid_package();


-- TRIGGERS ON REGISTERS/REDEEMS


-- Trigger to check for inserting/updating a registration/redemption of session.
-- 1) Check if register_date have already past the session_date itself
-- 2) Check if register_date have already past the registration_deadline
-- 3) Check if number of registration + redeems <= seating_capacity
-- 4) Check if customer register for more than 1 session in this course offering.
CREATE OR REPLACE FUNCTION reg_redeem_check()
    RETURNS trigger AS
$$
DECLARE
    deadline       date;
    s_date         date;
    seat_cap       int;
    num_registered int;

BEGIN

    SELECT registration_deadline
    INTO deadline
    FROM Offerings
    WHERE launch_date = new.launch_date
      AND course_id = new.course_id;

    SELECT seating_capacity, session_date
    INTO seat_cap, s_date
    FROM Sessions
             NATURAL JOIN Rooms
    WHERE new.sid = sid
      AND new.launch_date = launch_date
      AND new.course_id = course_id;

    SELECT COUNT(*)
    INTO num_registered
    FROM Redeems
    WHERE new.launch_date = launch_date
      AND new.course_id = course_id
      AND new.cust_id = cust_id;

    num_registered := num_registered + (SELECT COUNT(*)
                                        FROM Registers
                                        WHERE new.launch_date = launch_date
                                          AND new.course_id = course_id
                                          AND new.cust_id = cust_id);

    -- Check if register_date have already past the session_date or registration deadline
    IF (TG_TABLE_NAME = 'registers') THEN
        IF (NEW.register_date > deadline) THEN
            RAISE EXCEPTION 'It is too late to register for this session!';
        END IF;
    ELSE
        -- redeems
        IF (NEW.redeem_date > deadline) THEN
            RAISE EXCEPTION 'It is too late to register for this session!';
        END IF;
    END IF;

    -- Check if there is enough slots in the session
    IF (get_num_registration_for_session(new.sid, new.launch_date, new.course_id) > seat_cap) THEN
        RAISE EXCEPTION 'Session % with Course id: % and launch date: % is already full', new.sid, new.course_id, new.launch_date;
    END IF;

    -- Checks if customer has already registered for the session
    IF (num_registered >= 2) THEN
        RAISE EXCEPTION 'Customer has already registered for a session in this course offering!';
    END IF;
    RETURN new;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER valid_session
    AFTER INSERT OR UPDATE
    ON Redeems DEFERRABLE
    FOR EACH ROW
EXECUTE FUNCTION reg_redeem_check();

CREATE CONSTRAINT TRIGGER valid_session
    AFTER INSERT OR UPDATE
    ON Registers DEFERRABLE
    FOR EACH ROW
EXECUTE FUNCTION reg_redeem_check();



-- Handles refund of registrations if it is eligible for refund
CREATE OR REPLACE FUNCTION after_delete_of_registers()
    RETURNS TRIGGER AS
$$
DECLARE
    date_of_session DATE;
    cost            numeric;
BEGIN
    SELECT S.session_date
    INTO date_of_session
    FROM Sessions S
    WHERE S.sid = OLD.sid
      AND S.course_id = OLD.course_id
      AND S.launch_date = OLD.launch_date;

    IF (CURRENT_DATE + 7 <= date_of_session) THEN
        SELECT fees INTO cost FROM Offerings WHERE course_id = OLD.course_id AND launch_date = OLD.launch_date;
        INSERT INTO Cancels VALUES (NOW(), 0.9 * cost, NULL, OLD.cust_id, OLD.sid, OLD.launch_date, OLD.course_id);
    ELSE
        INSERT INTO Cancels VALUES (NOW(), 0, NULL, OLD.cust_id, OLD.sid, OLD.launch_date, OLD.course_id);
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER after_delete_of_registers
    AFTER DELETE
    ON Registers
    FOR EACH ROW
EXECUTE FUNCTION after_delete_of_registers();



-- Maintain the redemption count of customer's active/partially active package.
-- Enforce that each customer can have at most one active or partially active package
CREATE OR REPLACE FUNCTION modify_redeem_check()
    RETURNS TRIGGER AS
$$
DECLARE
    date_of_session DATE;
    num_packages    int;
BEGIN
    IF TG_OP = 'INSERT' THEN
        -- update redemption count
        UPDATE Buys B
        SET num_remaining_redemptions = num_remaining_redemptions - 1
        WHERE (B.buy_date, B.cust_id, B.package_id) = (NEW.buy_date, NEW.cust_id, NEW.package_id);

    ELSIF TG_OP = 'UPDATE' THEN

        IF ((NEW.buy_date, NEW.cust_id, NEW.package_id) <> (OLD.buy_date, OLD.cust_id, OLD.package_id)) THEN
            RAISE EXCEPTION 'Cannot directly modify package type for redeems table';
        END IF;

        -- Enforce that update maintains the at most one active/partially active constraint
        SELECT COUNT(*)
        INTO num_packages
        FROM Buys B
        WHERE cust_id = NEW.cust_id
          AND (num_remaining_redemptions > 0 OR
               EXISTS(SELECT 1
                      FROM Redeems R
                               NATURAL JOIN Sessions S
                      WHERE R.buy_date = B.buy_date
                        AND R.cust_id = B.cust_id
                        AND R.package_id = B.package_id
                        AND CURRENT_DATE + 7 <= S.session_date));

        IF (num_packages > 1) THEN
            RAISE EXCEPTION 'Updating the course session will result in multiple active/partially active package for Customer %', NEW.cust_id
                USING HINT = 'Use register_session and cancel_session to add and remove redeemed sessions';
        END IF;

    ELSE
        -- DELETE

        SELECT session_date
        INTO date_of_session
        FROM Sessions
        WHERE (sid, course_id, launch_date) = (OLD.sid, OLD.course_id, OLD.launch_date);

        -- handle the cancellation of session
        IF (CURRENT_DATE + 7 <= date_of_session) THEN
            UPDATE Buys B
            SET num_remaining_redemptions = num_remaining_redemptions + 1
            WHERE (B.buy_date, B.cust_id, B.package_id) = (NEW.buy_date, NEW.cust_id, NEW.package_id);

            INSERT INTO Cancels VALUES (NOW(), NULL, 1, OLD.cust_id, OLD.sid, OLD.launch_date, OLD.course_id);
        ELSE
            INSERT INTO Cancels VALUES (NOW(), NULL, 0, OLD.cust_id, OLD.sid, OLD.launch_date, OLD.course_id);
        END IF;

    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER modify_redeem_check
    AFTER INSERT OR UPDATE OR DELETE
    ON Redeems DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
EXECUTE FUNCTION modify_redeem_check();


-- TRIGGERS ON SESSIONS


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
    WHERE course_id = NEW.course_id
      AND launch_date = NEW.launch_date;

    IF (CURRENT_DATE > course_deadline) THEN
        RAISE EXCEPTION 'Course registration deadline have already PASSED!';
    END IF;

    -- check and enforce that the sid being inserted is in increasing order
    SELECT MAX(S.sid)
    INTO max_sid
    FROM Sessions S
    WHERE S.course_id = NEW.course_id
      AND S.launch_date = NEW.launch_date;

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

    SELECT DISTINCT CONCAT(duration, ' hours')::interval
    INTO span
    FROM Courses
    WHERE course_id = NEW.course_id;

    IF (NEW.start_time + span <> NEW.end_time) THEN
        RAISE EXCEPTION 'Invalid session hours. The session duration does not match with the specified Course duration';
    END IF;

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



-- Check if rooms of the sessions does not collide
CREATE OR REPLACE FUNCTION room_availability_checks()
    RETURNS TRIGGER AS
$$
BEGIN
    -- VALIDATE THE ROOM AVAILABILITY
    IF (1 < (SELECT COUNT(*)
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

CREATE CONSTRAINT TRIGGER room_availability_checks
    AFTER INSERT OR UPDATE
    ON Sessions DEFERRABLE
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
        SELECT COUNT(*)
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
    IF (TG_OP = 'UPDATE' AND NEW.eid = OLD.eid) THEN
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
               WHERE sid = OLD.sid
                 AND course_id = OLD.course_id
                 AND launch_date = OLD.launch_date)
        OR EXISTS(SELECT 1
                  FROM Redeems
                  WHERE sid = OLD.sid
                    AND course_id = OLD.course_id
                    AND launch_date = OLD.launch_date)) THEN
        RAISE EXCEPTION 'There is someone who registered for this session already';
        RETURN NULL;
    END IF;

    -- checks if the course session have already started

    IF (OLD.session_date < CURRENT_DATE OR (OLD.session_date = CURRENT_DATE AND OLD.start_time < CURRENT_TIME)) THEN
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



-- update start and end time and seating capacity of course offerings
CREATE OR REPLACE FUNCTION update_offerings_when_session_modified()
    RETURNS TRIGGER AS
$$
DECLARE
    min_date DATE;
    max_date DATE;
BEGIN

    IF (TG_OP IN ('INSERT', 'UPDATE')) THEN
        -- find the max and min of the session_date from that particular offering
        SELECT MIN(session_date), MAX(session_date)
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


    IF (TG_OP IN ('DELETE', 'UPDATE') AND
        EXISTS(SELECT 1 FROM Offerings WHERE (course_id, launch_date) = (OLD.course_id, OLD.launch_date))) THEN

        -- find the max and min of the session_date from that particular offering
        SELECT MIN(session_date), MAX(session_date)
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


-- TRIGGERS ON OFFERINGS


-- To ensure that the constraint of seat_cap >= target_num_reg when adding new course offering
-- As the seat capacity can fall below target when administrator, constraint check only on trigger
CREATE OR REPLACE FUNCTION seat_cap_at_least_target_reg()
    RETURNS TRIGGER AS
$$
BEGIN
    -- Check that seating capacity >= target registrations only when adding new offerings
    IF (NEW.seating_capacity < NEW.target_number_registrations) THEN
        RAISE EXCEPTION 'The total seating capacity must be at least equal to the target number of registrations';
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER seat_cap_at_least_target_reg
    AFTER INSERT
    ON Offerings DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
EXECUTE FUNCTION seat_cap_at_least_target_reg();


-- to ensure that course offerings will have >= 1
CREATE OR REPLACE FUNCTION after_insert_into_offerings()
    RETURNS TRIGGER AS
$$
BEGIN
    IF (NOT EXISTS(SELECT 1 FROM Sessions S WHERE S.launch_date = NEW.launch_date AND S.course_id = NEW.course_id)) THEN
        RAISE EXCEPTION 'There isnt any session in this course offerings: %', NEW.course_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER after_insert_into_offerings
    AFTER INSERT OR UPDATE
    ON Offerings DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
EXECUTE FUNCTION after_insert_into_offerings();


-- to ensure that the managers managing a course area has not departed/or is departing
CREATE OR REPLACE FUNCTION departed_administrator_check()
    RETURNS TRIGGER AS
$$
BEGIN
    IF (is_departed(NEW.eid, NEW.registration_deadline)) THEN
        RAISE EXCEPTION 'Administrator % is departing or has departed and cannot administrate the offering for course %', NEW.eid, NEW.course_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER departed_administrator_check
    AFTER INSERT OR UPDATE
    ON Offerings DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
EXECUTE FUNCTION departed_administrator_check();


-- TRIGGERS ON COURSE AREAS


-- to ensure that the managers managing a course area has not departed/or is departing
CREATE OR REPLACE FUNCTION departed_manager_check()
    RETURNS TRIGGER AS
$$
BEGIN
    -- if manager due to depart, he cannot be allowed to manage any areas
    IF ((SELECT depart_date FROM employees WHERE eid = NEW.eid) IS NOT NULL) THEN
        RAISE EXCEPTION 'Manager % is departing or has departed and cannot manage %', NEW.eid, NEW.area_name;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER departed_manager_check
    AFTER INSERT OR UPDATE
    ON Course_areas DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
EXECUTE FUNCTION departed_manager_check();


/*********************************
 * ROUTINES
 ********************************/

-- ROUTINE 1
--
-- Whether an employee is full-time or part-time is decided by the employee_cat input.
-- This will differentiate the salary_info input between monthly salary for a full-time
-- and hourly rate for a part-time.
--
-- salary_info input is not split into two to differentiate between full-time and
-- part-time due to the variadic course_areas input, which takes in a variable number
-- of course area input.
--
-- This means that the user needs to accurately pass in the correct type of salary_info
-- (monthly salary for full-time and hourly rate for part-time).
CREATE OR REPLACE PROCEDURE add_employee(_name text, _address text, _phone int, _email text,
                                         _salary_info numeric, _join_date date, _employee_cat text,
                                         VARIADIC _course_areas text[] DEFAULT NULL)
AS
$$
DECLARE
    _eid       int;
    _area_name text;
BEGIN
    -- validate _employee_cat
    IF _employee_cat NOT IN ('Manager', 'Administrator', 'Part-time instructor',
                             'Full-time instructor') THEN
        RAISE EXCEPTION 'Employee category must be from the following set: {Manager, Administrator, Part-time instructor, Full-time instructor}.';
    END IF;

    -- validate _course_areas
    IF _employee_cat IN ('Administrator') THEN
        IF _course_areas IS NOT NULL THEN
            RAISE EXCEPTION 'The set of course areas must be empty for an administrator.';
        END IF;
    ELSIF _employee_cat IN ('Manager') THEN
        -- the set of course area can be empty as a manager can manage zero course area
        IF _course_areas IS NOT NULL THEN
            FOREACH _area_name IN ARRAY _course_areas
                LOOP
                    -- the course area cannot be managed by another manager
                    IF _area_name IN (SELECT area_name FROM Course_areas) THEN
                        RAISE EXCEPTION '% is managed by another manager.', _area_name;
                    END IF;
                END LOOP;
        END IF;
    ELSE -- instructor
        IF _course_areas IS NULL THEN
            RAISE EXCEPTION 'The set of course areas cannot be empty for an instructor.';
        END IF;
    END IF;

    -- generate id
    SELECT COALESCE(MAX(eid), 0) + 1
    INTO _eid
    FROM Employees;

    -- insert into relevant tables
    INSERT INTO Employees
    VALUES (_eid, _name, _phone, _email, _address, _join_date, NULL);

    IF _employee_cat = 'Manager' THEN
        INSERT INTO Full_time_emp
        VALUES (_eid, _salary_info); -- assumed to be monthly salary

        INSERT INTO Managers
        VALUES (_eid);

        IF _course_areas IS NOT NULL THEN
            FOREACH _area_name IN ARRAY _course_areas
                LOOP
                    INSERT INTO Course_areas
                    VALUES (_area_name, _eid);
                END LOOP;
        END IF;
    ELSIF _employee_cat = 'Administrator' THEN
        INSERT INTO Full_time_emp
        VALUES (_eid, _salary_info); -- assumed to be monthly salary

        INSERT INTO Administrators
        VALUES (_eid);
    ELSIF _employee_cat = 'Part-time instructor' THEN
        INSERT INTO Part_time_emp
        VALUES (_eid, _salary_info); -- assumed to be hourly rate

        INSERT INTO Instructors
        VALUES (_eid);

        INSERT INTO Part_time_instructors
        VALUES (_eid);

        FOREACH _area_name IN ARRAY _course_areas
            LOOP
                INSERT INTO Specializes
                VALUES (_eid, _area_name);
            END LOOP;
    ELSE -- full-time instructor
        INSERT INTO Full_time_emp
        VALUES (_eid, _salary_info); -- assumed to be monthly salary

        INSERT INTO Instructors
        VALUES (_eid);

        INSERT INTO Full_time_instructors
        VALUES (_eid);

        FOREACH _area_name IN ARRAY _course_areas
            LOOP
                INSERT INTO Specializes
                VALUES (_eid, _area_name);
            END LOOP;
    END IF;
END;
$$ LANGUAGE plpgsql;


-- ROUTINE 2
-- Checking if update operation on Employees is valid is done by employee_trigger.
CREATE OR REPLACE PROCEDURE remove_employee(_eid int, _depart_date date)
AS
$$
BEGIN
    IF (_eid NOT IN (SELECT eid FROM employees)) THEN
        RAISE EXCEPTION 'Employee % does not exist', _eid;
    END IF;

    UPDATE Employees
    SET depart_date = _depart_date
    WHERE eid = _eid;
END;
$$ LANGUAGE plpgsql;


-- ROUTINE 3
-- Add customer and his credit card
CREATE OR REPLACE PROCEDURE add_customer(name text, address text, phone int, email text,
                                         card_number text, expiry_date date, CVV text)
AS
$$
DECLARE
    cid int;
BEGIN
    IF (expiry_date < CURRENT_DATE) THEN
        RAISE EXCEPTION 'Credit card expired: %', expiry_date
            USING HINT = 'Please check your expiry date';
    END IF;

    -- generate id
    SELECT COALESCE(MAX(cust_id), 0) + 1
    INTO cid
    FROM customers;

    -- insert into relevant tables
    INSERT INTO Customers
    VALUES (cid, name, address, phone, email);

    INSERT INTO Credit_cards
    VALUES (card_number, CVV, expiry_date, cid, NOW());
END
$$ LANGUAGE plpgsql;


-- ROUTINE 4
-- Used when a customer request to change credit card details
--     1. Creates new credit card when a new card number is used
--     2. Update (Reactivates) card details if card number is the same
CREATE OR REPLACE PROCEDURE update_credit_card(cid int, c_number text, c_expiry date, c_cvv text)
AS
$$
BEGIN
    IF (c_expiry < CURRENT_DATE) THEN
        RAISE EXCEPTION 'New credit card expired: %', c_expiry
            USING HINT = 'Please check your expiry date';

    ELSIF (NOT EXISTS(SELECT 1 FROM Customers WHERE cust_id = cid)) THEN
        RAISE EXCEPTION 'Non-existent customer id: %', cid
            USING HINT = 'Please check customer ID or use add_customer to add';

    END IF;

    IF (EXISTS(SELECT 1 FROM credit_cards WHERE cust_id = cid AND card_number = c_number)) THEN

        UPDATE Credit_cards
        SET from_date   = NOW(),
            expiry_date = c_expiry,
            CVV         = c_cvv
        WHERE cust_id = cid
          AND card_number = c_number;
    ELSE
        INSERT INTO Credit_cards
        VALUES (c_number, c_cvv, c_expiry, cid, NOW());
    END IF;
END
$$ LANGUAGE plpgsql;


-- ROUTINE 5
-- Adds a course into the courses table
CREATE OR REPLACE PROCEDURE add_course(course_title text, course_desc text, course_area text, duration integer) AS
$$
INSERT INTO Courses
VALUES (COALESCE((SELECT MAX(course_id) FROM Courses), 0) + 1, course_title, course_desc, course_area, duration);
$$ LANGUAGE sql;


-- ROUTINE 6
-- Finds all the instructors who could be assigned to teach a course session.
CREATE OR REPLACE FUNCTION find_instructors(IN in_cid int, IN in_session_date date, IN in_start_hour time)
    RETURNS TABLE
            (
                eid  int,
                name text
            )
AS
$$
DECLARE
    span          INT;
    end_hour      time;
    one_hour      interval := CONCAT(1, ' hours')::interval;
    span_interval interval;
BEGIN
    IF (in_cid NOT IN (SELECT course_id FROM Courses)) THEN
        RAISE EXCEPTION 'Course % does not exist', in_cid;
    END IF;

    -- validate session_date
    IF (SELECT EXTRACT(ISODOW FROM in_session_date) IN (6, 7)) THEN
        RAISE EXCEPTION 'Session_date must be a weekday';
    END IF;

    -- validate start_hour
    IF (in_start_hour < TIME '09:00') THEN
        RAISE EXCEPTION 'Cannot have a session before 9am';
    END IF;

    SELECT duration INTO span FROM Courses WHERE Courses.course_id = in_cid;
    span_interval := CONCAT(span, ' hours')::interval;
    -- validate session_date + duration
    IF ((in_start_hour, in_start_hour + span_interval) OVERLAPS (TIME '12:00', TIME '14:00') OR
        (in_start_hour + span_interval > TIME '18:00')) THEN
        RAISE EXCEPTION 'Invalid start time! It might have overlapped with lunch time or end work timing';
    END IF;

    end_hour := in_start_hour + span_interval;
    RETURN QUERY
        WITH R0 AS (SELECT DISTINCT Q0.eid, Q0.name
                    FROM ((SELECT * FROM Courses WHERE Courses.course_id = in_cid) AS TEMP1
                        NATURAL JOIN Specializes
                        NATURAL JOIN (SELECT *
                                      FROM Employees E
                                      WHERE NOT is_departed(E.eid, in_session_date)) AS TEMP2) AS Q0
        ),
             R1 AS (SELECT DISTINCT Q1.eid, Q1.name
                    FROM (SELECT *
                          FROM R0
                                   NATURAL JOIN Part_time_instructors) AS Q1
                    WHERE NOT EXISTS(
                            SELECT 1
                            FROM Sessions S1
                            WHERE S1.eid = Q1.eid
                              AND (((in_start_hour, end_hour) OVERLAPS
                                    (S1.start_time - one_hour, S1.end_time + one_hour) AND
                                    S1.session_date = in_session_date)
                                OR (SELECT get_hours(Q1.eid, in_session_date)) + span > 30)
                        )
             ),
             R2 AS (SELECT DISTINCT Q2.eid, Q2.name
                    FROM (SELECT *
                          FROM R0
                                   NATURAL JOIN Full_time_instructors) AS Q2
                    WHERE NOT EXISTS(
                            SELECT 1
                            FROM Sessions S1
                            WHERE S1.session_date = in_session_date
                              AND S1.eid = Q2.eid
                              AND (in_start_hour, end_hour) OVERLAPS (S1.start_time - one_hour, S1.end_time + one_hour)
                        )
             )

        SELECT *
        FROM R1
        UNION
        SELECT *
        FROM R2;
END;
$$ LANGUAGE plpgsql;


-- ROUTINE 7
--
-- R0 denotes employees who are specializes in that course area
-- R1 DENOTES {start_date, ..., end_date} each increment in per day
-- R2 Checks through the part_time_instructors and select those whose total hours + duration <= 30 and and the day which
-- Iterate though should only contain mon-fri and check if there is any availability for that day itself
-- R3 checks through the full time instructors and select those whose days are available.
CREATE OR REPLACE FUNCTION get_available_instructors(IN in_cid INT, IN in_start_date date, IN in_end_date date)
    RETURNS TABLE
            (
                eid             INT,
                name            TEXT,
                hours           INT,
                day             date,
                available_hours Time[]
            )
AS
$$
DECLARE
    span int;
BEGIN
    IF NOT EXISTS(SELECT 1 FROM Courses WHERE course_id = in_cid) THEN
        RAISE EXCEPTION 'Course % does not exist', in_cid;
    END IF;

    SELECT duration INTO span FROM Courses WHERE Courses.course_id = in_cid;

    RETURN QUERY
        WITH R0 AS (SELECT DISTINCT Q0.eid, Q0.name, Q0.depart_date
                    FROM ((SELECT C.area_name FROM Courses C WHERE C.course_id = in_cid) AS TEMP1
                        NATURAL JOIN Specializes
                        NATURAL JOIN (SELECT E.eid, E.depart_date, E.name FROM Employees E) AS TEMP2) AS Q0
        ),
             R1 AS (SELECT CAST(s_day AS date) FROM GENERATE_SERIES(in_start_date, in_end_date, '1 day') AS S(s_day)),
             R2 AS (SELECT DISTINCT Q2.eid,
                                    Q2.name,
                                    (SELECT get_hours(Q2.eid, Q2.s_day)),
                                    Q2.s_day,
                                    (SELECT check_availability(Q2.eid, span, Q2.s_day))
                    FROM (R0 NATURAL JOIN Part_time_instructors CROSS JOIN R1) AS Q2
                    WHERE NOT is_departed(Q2.eid, Q2.s_day)
                      AND (SELECT get_hours(Q2.eid, Q2.s_day)) + span <= 30
                      AND (SELECT EXTRACT(DOW FROM Q2.s_day) IN (1, 2, 3, 4, 5))
                      AND (ARRAY_LENGTH(check_availability(Q2.eid, span, Q2.s_day), 1)) <> 0
             ),
             R3 AS (SELECT DISTINCT Q3.eid,
                                    Q3.name,
                                    (SELECT get_hours(Q3.eid, Q3.s_day)),
                                    Q3.s_day,
                                    (SELECT check_availability(Q3.eid, span, Q3.s_day))
                    FROM (R0 NATURAL JOIN Full_time_instructors CROSS JOIN R1) AS Q3
                    WHERE NOT is_departed(Q3.eid, Q3.s_day)
                      AND (SELECT EXTRACT(DOW FROM Q3.s_day) IN (1, 2, 3, 4, 5))
                      AND (ARRAY_LENGTH(check_availability(Q3.eid, span, Q3.s_day), 1)) <> 0
             )
        SELECT *
        FROM R2
        UNION
        SELECT *
        FROM R3
        ORDER BY eid ASC, s_day ASC;
END;
$$ LANGUAGE plpgsql;


-- ROUTINE 8
--
-- assume session_duration are in units of hour
CREATE OR REPLACE FUNCTION find_rooms(_session_date date, _session_start_hour time,
                                      _session_duration int)
    RETURNS TABLE
            (
                _rid int
            )
AS
$$
DECLARE
    curs CURSOR FOR (SELECT *
                     FROM Rooms
                     ORDER BY rid);
    r                   record;
    _session_start_time time;
    _session_end_time   time;
BEGIN
    -- validate session_date
    IF (SELECT EXTRACT(ISODOW FROM _session_date) IN (6, 7)) THEN
        RAISE EXCEPTION 'Session date must be a weekday.';
    END IF;

    -- validate session_start_time and session_end_time
    _session_start_time := _session_start_hour;
    _session_end_time := _session_start_hour + CONCAT(_session_duration, ' hours')::interval;
    IF (NOT (_session_start_time, _session_end_time) OVERLAPS (time '09:00', time '18:00'))
        OR (_session_start_time, _session_end_time) OVERLAPS (time '12:00', time '14:00') THEN
        RAISE EXCEPTION 'Session start time and/or duration is/are invalid.';
    END IF;

    OPEN curs;
    LOOP
        FETCH curs INTO r;
        EXIT WHEN NOT found;

        -- assume start_time and end_time are in units of hour
        IF NOT EXISTS(
                SELECT 1
                FROM Sessions
                WHERE rid = r.rid
                  AND session_date = _session_date
                  AND (start_time, end_time) OVERLAPS (_session_start_time, _session_end_time)) THEN
            _rid := r.rid;
            RETURN NEXT;
        END IF;
    END LOOP;
    CLOSE curs;
END;
$$ LANGUAGE plpgsql;


-- ROUTINE 9
-- Get available rooms in a given range of date
-- assume a room is only available during the weekday from 9am to 6pm (except 12pm to 2pm)
CREATE OR REPLACE FUNCTION get_available_rooms(_start_date date, _end_date date)
    RETURNS TABLE
            (
                _rid             int,
                _room_capacity   int,
                _day             date,
                _available_hours time[]
            )
AS
$$
DECLARE
    curs CURSOR FOR (SELECT *
                     FROM Rooms
                     ORDER BY rid);
    r                record;
    _hours_array     time[];
    _hour            time;
    _loop_date       date;
    _temp_start_hour time;
    _temp_end_hour   time;
BEGIN
    -- validate that _start_date is before _end_date
    IF (_start_date > _end_date) THEN
        RAISE EXCEPTION 'The start date cannot be after the end date.';
    END IF;

    _hours_array :=
            ARRAY [time '09:00', time '10:00', time '11:00', time '14:00', time '15:00', time '16:00', time '17:00'];

    OPEN curs;
    -- loop each rid
    LOOP
        FETCH curs INTO r;
        EXIT WHEN NOT found;

        -- loop each day for the current rid
        _loop_date := _start_date;
        LOOP
            EXIT WHEN _loop_date > _end_date;

            IF (SELECT EXTRACT(ISODOW FROM _loop_date) IN (1, 2, 3, 4, 5)) THEN
                _rid = r.rid;
                _room_capacity := r.seating_capacity;
                _day := _loop_date;
                _available_hours := '{}';

                -- loop each hour for the current rid and day
                FOREACH _hour IN ARRAY _hours_array
                    LOOP
                        _temp_start_hour := _hour;
                        _temp_end_hour := _hour + INTERVAL '1 hour';

                        IF NOT EXISTS(
                                SELECT 1
                                FROM Sessions
                                WHERE rid = _rid
                                  AND session_date = _loop_date
                                  AND (start_time, end_time) OVERLAPS (_temp_start_hour, _temp_end_hour)) THEN
                            _available_hours := ARRAY_APPEND(_available_hours, _hour);
                        END IF;
                    END LOOP;

                IF (ARRAY_LENGTH(_available_hours, 1) > 0) THEN
                    RETURN NEXT;
                END IF;
            END IF;

            _loop_date := _loop_date + 1;
        END LOOP;

    END LOOP;
    CLOSE curs;
END;
$$ LANGUAGE plpgsql;


-- ROUTINE 10
-- Check for
-- 1. Valid course offering
-- 2. Sufficient instructors to add all of sessions
-- Use an array to keep track of all the new session_ids added.
-- Greedy assignment to get a valid instructor assignment.
CREATE OR REPLACE PROCEDURE add_course_offering(cid int, l_date date, fees numeric, reg_deadline date,
                                                target_num int, admin_id int, sessions_arr text[][]) AS
$$
DECLARE
    temp            text[];
    eid_rec         record;
    chosen_session  record;
    one_hour        interval := '1 hour'::interval;
    course_duration int;
    next_sid        int;
    s_date          date;
    s_time          time;
    s_rid           int;
BEGIN
    -- 	Checking validity of course offering information
    IF (ARRAY_LENGTH(sessions_arr, 1) = 0 OR reg_deadline < CURRENT_DATE) THEN
        RAISE EXCEPTION 'Course offering details are invalid';
    END IF;

    SELECT duration
    INTO course_duration
    FROM Courses
    WHERE course_id = cid;

    IF (EXISTS(SELECT 1 FROM Offerings WHERE (launch_date, course_id) = (l_date, cid))) THEN
        RAISE EXCEPTION 'Course offering for course % launching on % already exists', cid, l_date;
    END IF;

    CREATE TEMPORARY TABLE IF NOT EXISTS assignment_table
    (
        sid          int,
        session_date date,
        start_time   time,
        end_time     time,
        rid          int,
        eid          int,

        PRIMARY KEY (session_date, start_time, rid, eid)
    ) ON COMMIT DROP;

    -- ASSERT (select count(*) from assignment_table) = 0;

    next_sid := 1;
    FOREACH temp SLICE 1 IN ARRAY sessions_arr
        LOOP
            IF (ARRAY_LENGTH(temp, 1) <> 3) THEN
                RAISE EXCEPTION 'Please provide the session date, start time and room identifier for each session';
            END IF;

            s_date := temp[1]::date;
            s_time := temp[2]::time;
            s_rid := temp[3]::int;

            -- Add all possible session assignments into assignment table
            FOR eid_rec IN (SELECT * FROM find_instructors(cid, s_date, s_time))
                LOOP
                    INSERT INTO assignment_table
                    VALUES (next_sid, s_date, s_time, s_time + CONCAT(course_duration, ' hours')::interval, s_rid,
                            eid_rec.eid);
                END LOOP;

            next_sid := next_sid + 1;
        END LOOP;

    CREATE TEMPORARY TABLE IF NOT EXISTS assigned_sessions
    (
        sid          int,
        launch_date  date,
        cid          int,
        session_date date,
        start_time   time,
        end_time     time,
        rid          int,
        eid          int,

        PRIMARY KEY (session_date, start_time, rid, eid)
    ) ON COMMIT DROP;

    -- Assign instructors and add sessions into sessions table
    WHILE EXISTS(SELECT 1 FROM assignment_table)
        LOOP
        -- Greedily select an assignment by choosing least choice_count followed by least desire_count
        -- Choice_count refers to number of possible instructor assignments for a given session
        -- Desire count refers to the number of clashes with other assignments
            WITH weighted_choice AS (
                -- number of instructor choices for a session
                SELECT session_date, start_time, rid, COUNT(*) AS choice_count
                FROM assignment_table
                GROUP BY (session_date, start_time, rid)
            ),
                 weighted_desire AS (
                     SELECT DISTINCT session_date,
                                     start_time,
                                     eid,
                                     (SELECT COUNT(*)
                                      FROM assignment_table B
                                      WHERE (A.session_date, A.eid) = (B.session_date, B.eid)
                                        AND (A.start_time - one_hour, A.end_time + one_hour) OVERLAPS
                                            (B.start_time, B.end_time)
                                     ) AS desire_count
                     FROM assignment_table A
                 )
            SELECT *
            INTO chosen_session
            FROM assignment_table
                     NATURAL JOIN weighted_choice
                     NATURAL JOIN weighted_desire
            ORDER BY choice_count ASC, desire_count ASC
            LIMIT 1;

            -- Add chosen assignment to session
            INSERT INTO assigned_sessions
            VALUES (chosen_session.sid, l_date, cid,
                    chosen_session.session_date, chosen_session.start_time, chosen_session.end_time,
                    chosen_session.rid, chosen_session.eid);

            -- Update assignment table remove clashing slots if
            -- 1. Remove all assignments that assigns to the chosen session
            -- 2. Remove all assignments that clashes with the chosen session (same room, eid and clashing time w breaks)
            DELETE
            FROM assignment_table
            WHERE (chosen_session.session_date, chosen_session.start_time, chosen_session.rid) =
                  (session_date, start_time, rid)
               OR ((chosen_session.session_date, chosen_session.eid) = (session_date, eid) AND
                   (chosen_session.start_time - one_hour, chosen_session.end_time + one_hour) OVERLAPS
                   (start_time, end_time));

            -- 3. Remove all part-time instructors who exceed the 30h limit in a month
            IF (chosen_session.eid IN (SELECT * FROM Part_time_instructors) AND
                get_hours(chosen_session.eid, chosen_session.session_date) + course_duration > 30) THEN

                DELETE
                FROM assignment_table
                WHERE chosen_session.eid = eid
                  AND EXTRACT(MONTH FROM chosen_session.session_date) = EXTRACT(MONTH FROM session_date);
            END IF;
        END LOOP;

    IF ((SELECT COUNT(*) FROM assigned_sessions) <> ARRAY_LENGTH(sessions_arr, 1)) THEN
        RAISE EXCEPTION 'No valid instructor assignment found';
    END IF;

    -- Add Offerings
    -- Placeholder session start, end date and seat capacity
    -- Session trigger will update the dates and seat capacity
    INSERT INTO Offerings
    VALUES (l_date, cid, reg_deadline, reg_deadline + 10, reg_deadline + 10, admin_id, target_num, target_num, fees);

    -- Add Sessions
    INSERT INTO Sessions
    SELECT *
    FROM assigned_sessions S
    ORDER BY S.sid;

    DROP TABLE assignment_table;
    DROP TABLE assigned_sessions;
END;
$$ LANGUAGE plpgsql;


-- ROUTINE 11
CREATE OR REPLACE PROCEDURE add_course_package(name text, num_sessions int,
                                               start_date date, end_date date, price numeric)
AS
$$
DECLARE
    pid int;
BEGIN
    -- generate id
    SELECT COALESCE(MAX(package_id), 0) + 1
    INTO pid
    FROM course_packages;

    -- insert into course packages
    INSERT INTO course_packages
    VALUES (pid, name, num_sessions, price, start_date, end_date);
END
$$ LANGUAGE plpgsql;


-- ROUTINE 12
-- used to retrieve course packages that are available for sale
CREATE OR REPLACE FUNCTION get_available_course_packages()
    RETURNS TABLE
            (
                name                     text,
                num_free_course_sessions int,
                end_date                 date,
                price                    numeric
            )
AS
$$
SELECT name, num_free_registrations, sale_end_date, price
FROM course_packages
WHERE CURRENT_DATE BETWEEN sale_start_date AND sale_end_date
ORDER BY sale_end_date ASC;
$$ LANGUAGE sql;


-- ROUTINE 13
-- Used when customer requests to purchase a course package
CREATE OR REPLACE PROCEDURE buy_course_package(cid int, pid int)
AS
$$
DECLARE
    active_card   Credit_cards;
    n_redemptions int;
BEGIN
    -- get required details
    SELECT * INTO active_card FROM get_active_card(cid);

    SELECT num_free_registrations
    INTO n_redemptions
    FROM Course_packages C
    WHERE C.package_id = pid;

    IF NOT found THEN
        RAISE EXCEPTION 'Course package % does not exist', pid;
    END IF;

    -- buying course package
    INSERT INTO Buys
    VALUES (CURRENT_DATE, cid, active_card.card_number, pid, n_redemptions);
END
$$ LANGUAGE plpgsql;


-- ROUTINE 14
-- used when a customer requests to view his/her active/partially active course package
CREATE OR REPLACE FUNCTION get_my_course_package(cid int)
    RETURNS json AS
$$
DECLARE
    active_package    record;
    redeemed_sessions json;
    out_json          json;
BEGIN

    SELECT *
    INTO active_package
    FROM Buys B
    WHERE cust_id = cid
      AND (num_remaining_redemptions > 0 OR
           EXISTS(SELECT 1
                  FROM Redeems R
                           NATURAL JOIN Sessions S
                  WHERE R.cust_id = cid
                    AND R.buy_date = B.buy_date
                    AND R.package_id = B.package_id
                    AND CURRENT_DATE + 7 <= S.session_date));

    IF NOT found THEN
        RAISE INFO 'No active/partially active course package for customer %', cid;
        RETURN out_json;
    END IF;

    SELECT ARRAY_TO_JSON(ARRAY_AGG(t))
    INTO redeemed_sessions
    FROM (
             SELECT title AS course_name, session_date, start_time AS session_start_time
             FROM Redeems R
                      NATURAL JOIN Sessions
                      NATURAL JOIN Courses
             WHERE active_package.cust_id = R.cust_id
               AND active_package.buy_date = R.buy_date
               AND active_package.package_id = R.package_id
             ORDER BY session_date ASC,
                      start_time ASC
         ) t;


    SELECT ROW_TO_JSON(p)
    INTO out_json
    FROM (
             SELECT C.name                                   AS package_name,
                    active_package.buy_date                  AS purchase_date,
                    price,
                    num_free_registrations                   AS num_free_sessions,
                    active_package.num_remaining_redemptions AS num_remaining_sessions,
                    redeemed_sessions
             FROM Course_packages C
             WHERE active_package.package_id = C.package_id
         ) p;

    RETURN out_json;
END
$$ LANGUAGE plpgsql;


-- ROUTINE 15
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
                fees                  numeric,
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
WHERE registration_deadline >= CURRENT_DATE
  AND seating_capacity - COALESCE(numReg, 0) > 0
ORDER BY registration_deadline, title;
$$ LANGUAGE sql;


-- ROUTINE 16
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
  AND (session_date > CURRENT_DATE OR session_date = CURRENT_DATE AND start_time >= CURRENT_TIME)
  AND seating_capacity - get_num_registration_for_session(sid, date_of_launch, cid) > 0
ORDER BY session_date, start_time;
$$ LANGUAGE sql;


-- ROUTINE 17
-- 1) Check if current_date have already past the session_date itself
-- 2) Check if current_date have already past the registration_deadline
-- 3) Check if number of registration + redeems <= seating_capacity
-- 4) If redeems, check if the number of redeems of that package_id < num_free_registrations. Means check if package is active?
-- 5) Check if there is any session of this course that exist before (In unique_session_per_course_redeem_checks AND unique_session_per_course_register_checks)
CREATE OR REPLACE PROCEDURE register_session(cus_id INT, in_cid INT, date_of_launch DATE, session_number INT,
                                             pay_method TEXT)
AS
$$
DECLARE
    pid         int;
    num_card    TEXT;
    date_of_buy DATE;
BEGIN

    IF (pay_method = 'redeem') THEN

        SELECT buy_date, package_id
        INTO date_of_buy, pid
        FROM Buys B
        WHERE B.cust_id = cus_id
          AND B.num_remaining_redemptions > 0;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Customer % does not have an active course package that is available for free redemptions', cus_id;
        END IF;

        INSERT INTO Redeems VALUES (CURRENT_DATE, date_of_buy, cus_id, pid, session_number, date_of_launch, in_cid);

    ELSIF (pay_method = 'card') THEN
        SELECT card_number INTO num_card FROM get_active_card(cus_id);

        INSERT INTO Registers VALUES (CURRENT_DATE, cus_id, num_card, session_number, date_of_launch, in_cid);
    ELSE
        RAISE EXCEPTION 'INVALID PAYMENT METHOD';
    END IF;
END;
$$ LANGUAGE plpgsql;


-- ROUTINE 18
CREATE OR REPLACE FUNCTION get_my_registrations(IN cus_id INT)
    RETURNS TABLE
            (
                course_name     TEXT,
                course_fee      numeric,
                session_date    DATE,
                start_hour      TIME,
                duration        INT,
                instructor_name TEXT
            )
AS
$$
DECLARE
BEGIN
    RETURN QUERY
        WITH Q0 AS (SELECT launch_date, course_id, fees FROM Offerings),
             Q1 AS (SELECT *
                    FROM (Employees
                             NATURAL JOIN Specializes
                             NATURAL JOIN Courses
                             NATURAL JOIN Q0
                             NATURAL JOIN Sessions)),
             Q2 AS (SELECT * FROM (Q1 NATURAL JOIN Redeems) A WHERE cust_id = cus_id AND A.session_date > CURRENT_DATE),
             Q3 AS (SELECT *
                    FROM (Q1 NATURAL JOIN Registers) B
                    WHERE cust_id = cus_id
                      AND B.session_date > CURRENT_DATE)
        SELECT *
        FROM (SELECT Q2.title, Q2.fees, Q2.session_date, Q2.start_time, Q2.duration, Q2.name
              FROM Q2
              UNION
              SELECT Q3.title, Q3.fees, Q3.session_date, Q3.start_time, Q3.duration, Q3.name
              FROM Q3) AS ANS
        ORDER BY (ANS.session_date, ANS.start_time);
END;
$$ LANGUAGE plpgsql;


-- ROUTINE 19
-- 1. Check for seat availability is done by trigger
-- 2. Check if customers registered or redeemed for the session and update accordingly
-- 3. Check for current_date before registration deadline
CREATE OR REPLACE PROCEDURE update_course_session(customer_id int, cid int, date_launch date, new_sid int) AS
$$
BEGIN
    IF (NOT EXISTS(SELECT 1 FROM Customers WHERE cust_id = customer_id)) THEN
        RAISE EXCEPTION 'Customer % does not exist', customer_id;
    END IF;

    IF (EXISTS(
            SELECT 1 FROM Redeems WHERE cust_id = customer_id AND course_id = cid AND launch_date = date_launch)) THEN

        UPDATE Redeems
        SET sid         = new_sid,
            redeem_date = CURRENT_DATE
        WHERE cust_id = customer_id
          AND course_id = cid
          AND launch_date = date_launch;
    ELSIF (EXISTS(
            SELECT 1 FROM registers WHERE cust_id = customer_id AND course_id = cid AND launch_date = date_launch)) THEN
        UPDATE Registers
        SET sid           = new_sid,
            register_date = CURRENT_DATE
        WHERE cust_id = customer_id
          AND course_id = cid
          AND launch_date = date_launch;
    ELSE
        RAISE EXCEPTION 'Customer % does not have a registered session for course offering (%, %)', customer_id, cid, date_launch;
    END IF;
END;
$$ LANGUAGE plpgsql;


-- ROUTINE 20
-- Cancels a registered course session
CREATE OR REPLACE PROCEDURE cancel_registration(cus_id INT, in_cid INT, date_of_launch DATE)
AS
$$
DECLARE
    sid_register INT;
    sid_redeem   INT;
BEGIN
    -- we know that for a course, that customer only have 1 session
    -- if cancelled at least 7 days before the day of registered sessions, will have to credit an extra course session to customer
    SELECT R.sid
    INTO sid_redeem
    FROM Redeems R
    WHERE R.cust_id = cus_id
      AND R.course_id = in_cid
      AND R.launch_date = date_of_launch;

    SELECT R.sid
    INTO sid_register
    FROM Registers R
    WHERE R.cust_id = cus_id
      AND R.course_id = in_cid
      AND R.launch_date = date_of_launch;

    IF (sid_redeem IS NULL AND sid_register IS NULL) THEN
        RAISE EXCEPTION 'This customer does not have any session for this course';
    END IF;

    IF (sid_redeem IS NOT NULL) THEN
        -- DELETE FROM redeems
        DELETE
        FROM Redeems R
        WHERE R.cust_id = cus_id
          AND R.course_id = in_cid
          AND R.launch_date = date_of_launch;
    ELSE
        -- DELETE FROM registers
        DELETE
        FROM Registers R
        WHERE R.cust_id = cus_id
          AND R.course_id = in_cid
          AND R.launch_date = date_of_launch;
    END IF;
END;
$$ LANGUAGE plpgsql;


-- ROUTINE 21
-- Things to check:
-- 1) If session_date is later than current_date (Done)
-- 2) Check if on that day for the new EID, there is any overlaps with his old timing (in instructors_overlap_timing_checks)
-- 3) If part-time instructor, check that the sum of all his timing + new duration for this month <= 30 (in instructors_part_time_duration_checks)
-- 4) Check if instructor specializes in that course (in instructors_specialization_checks)
CREATE OR REPLACE PROCEDURE update_instructor(in_cid INT, date_of_launch DATE, in_sid INT, new_eid INT)
AS
$$
DECLARE
    s_date   date;
    s_time   time;
    prev_eid int;
BEGIN
    SELECT S.session_date, S.start_time, S.eid
    INTO s_date, s_time, prev_eid
    FROM Sessions S
    WHERE S.sid = in_sid
      AND S.launch_date = date_of_launch
      AND S.course_id = in_cid;

    IF (CURRENT_DATE > s_date OR (CURRENT_DATE = s_date AND CURRENT_TIME > s_time)) THEN
        RAISE EXCEPTION 'This session has already passed';
    END IF;

    UPDATE Sessions
    SET eid = new_eid
    WHERE (sid, launch_date, course_id) = (in_sid, date_of_launch, in_cid)
      AND eid = prev_eid;
END;
$$ LANGUAGE plpgsql;


-- ROUTINE 22
-- launch_date is needed to differentiate between two sessions with the same
-- course id and same session number but offered at different times of the year
-- (i.e. different launch_date)
CREATE OR REPLACE PROCEDURE update_room(_cid int, _launch_date date, _session_num int, _new_rid int)
AS
$$
DECLARE
    _session_date      date;
    _session_time      time;
    _new_room_capacity int;
    _num_of_redeem     int;
    _num_of_register   int;
BEGIN
    -- check if session exists
    IF NOT EXISTS(
            SELECT 1
            FROM Sessions
            WHERE course_id = _cid
              AND launch_date = _launch_date
              AND sid = _session_num) THEN
        RAISE EXCEPTION 'Course session does not exist.';
    END IF;

    -- check that session has not started yet
    SELECT session_date, start_time
    INTO _session_date, _session_time
    FROM Sessions
    WHERE course_id = _cid
      AND launch_date = _launch_date
      AND sid = _session_num;

    IF _session_date < CURRENT_DATE
        OR (_session_date = CURRENT_DATE AND _session_time <= CURRENT_TIME) THEN
        RAISE EXCEPTION 'Room is not updated as the session has already started.';
    END IF;

    -- check if new_rid exists in Rooms
    IF _new_rid NOT IN (SELECT rid FROM Rooms) THEN
        RAISE EXCEPTION 'The new room does not exist in the Rooms table.';
    END IF;

    -- check if number of registrations exceed seating capacity of new room
    SELECT seating_capacity
    INTO _new_room_capacity
    FROM Rooms
    WHERE rid = _new_rid;

    SELECT COUNT(cust_id)
    INTO _num_of_redeem
    FROM Redeems
    WHERE course_id = _cid
      AND launch_date = _launch_date
      AND sid = _session_num;

    SELECT COUNT(cust_id)
    INTO _num_of_register
    FROM Registers
    WHERE course_id = _cid
      AND launch_date = _launch_date
      AND sid = _session_num;

    IF _new_room_capacity < (_num_of_redeem + _num_of_register) THEN
        RAISE EXCEPTION 'The number of registrations exceeds the seating capacity of the new room.';
    END IF;

    -- update room for the session
    UPDATE Sessions
    SET rid = _new_rid
    WHERE course_id = _cid
      AND launch_date = _launch_date
      AND sid = _session_num;
END;
$$ LANGUAGE plpgsql;


-- ROUTINE 23
-- Remove the specified session
CREATE OR REPLACE PROCEDURE remove_session(in_cid INT, date_of_launch DATE, in_sid INT)
AS
$$
BEGIN
    IF (NOT EXISTS(SELECT 1 FROM Sessions WHERE (course_id, launch_date, sid) = (in_cid, date_of_launch, in_sid))) THEN
        RAISE EXCEPTION 'The session (%, %, %) does not exist', in_cid, date_of_launch, in_sid;
    END IF;

    DELETE
    FROM Sessions S
    WHERE S.course_id = in_cid
      AND S.sid = in_sid
      AND S.launch_date = date_of_launch;
END;
$$ LANGUAGE plpgsql;


-- ROUTINE 24
-- Trigger - to enforce total participation, every Offerings has >= 1 Sessions (CONSTRAINT TYPE) (PERSPECTIVE: OFFERINGS?)
-- Trigger - start date and end date of Offerings is updated to the earliest and latest session_date (UPDATE TYPE) (Done)
-- Trigger - update seating_capacity in Offerings to sum of seating capacities of sessions (UPDATE TYPE)  (Done)
-- Trigger - the assigned instructor must specialise in that course_area (CONSTRAINT TYPE) (Done) (in instructors_specialization_checks)
-- Trigger - each part-time instructor total hours per month <= 30 (CONSTRAINT TYPE) (Done) (in instructors_part_time_duration_checks)
-- Trigger - each instructor at most one course session at any hour (CONSTRAINT TYPE) (Done) (in instructors_overlap_timing_checks)
-- Trigger - each instructor must not teach 2 consecutive sessions (1 hr break) (CONSTRAINT TYPE) (Done) (in instructors_overlap_timing_checks)
-- Trigger - Each room can be used to conduct at most one course session at any time (CONSTRAINT TYPE) (Done) (in room_availability_checks)
-- Trigger - New sessions added should not collide with lunch time or start or end timing (IN new_session_timing_collision_checks)
-- Trigger - Course offering have to exist first before adding session (in course_offering_exists)
CREATE OR REPLACE PROCEDURE add_session(in_cid INT, date_of_launch DATE, session_number INT, in_session_date DATE,
                                        in_start_hour TIME, in_eid INT, in_rid INT)
AS
$$
DECLARE
    span interval;
BEGIN
    SELECT DISTINCT CONCAT(duration, ' hours')::interval
    INTO span
    FROM Courses
    WHERE course_id = in_cid;

    INSERT INTO Sessions
    VALUES (session_number, date_of_launch, in_cid, in_session_date, in_start_hour, in_start_hour + span, in_rid,
            in_eid);

END;
$$ LANGUAGE plpgsql;


-- ROUTINE 25
-- Number of work hours for a part-time instructor is computed based on the number of hours
-- the part-time instructor taught at all sessions for that particular month and year.
CREATE OR REPLACE FUNCTION pay_salary()
    RETURNS TABLE
            (
                _eid            int,
                _name           text,
                _status         text,
                _num_work_days  int,
                _num_work_hours int,
                _hourly_rate    numeric,
                _monthly_salary numeric,
                _amount         numeric
            )
AS
$$
DECLARE
    curs CURSOR FOR (SELECT *
                     FROM employees
                     ORDER BY eid);
    r               record;
    _pay_month      int;
    _pay_year       int;
    _num_of_days    int;
    _join_date      date;
    _depart_date    date;
    _first_work_day int;
    _last_work_day  int;
    _pay_date       date;
BEGIN
    _pay_month := EXTRACT(MONTH FROM CURRENT_DATE)::int;
    _pay_year := EXTRACT(YEAR FROM CURRENT_DATE)::int;

    OPEN curs;
    LOOP
        FETCH curs INTO r;
        EXIT WHEN NOT found;

        _eid := r.eid;
        _name := r.name;

        IF _eid NOT IN (SELECT eid FROM Employees WHERE depart_date < MAKE_DATE(_pay_year, _pay_month, 1)) THEN
            IF _eid IN (SELECT eid FROM Part_time_emp) THEN
                _status := 'Part-time';
                _num_work_days := NULL;

                -- compute number of hours worked by the part-time instructor
                -- assume start_time and end_time are in units of hour
                SELECT COALESCE(SUM(EXTRACT(HOUR FROM end_time) - EXTRACT(HOUR FROM start_time))::int, 0)
                INTO _num_work_hours
                FROM Sessions
                WHERE eid = _eid
                  AND _pay_month = (EXTRACT(MONTH FROM session_date))::int
                  AND _pay_year = (EXTRACT(YEAR FROM session_date))::int;

                SELECT hourly_rate
                INTO _hourly_rate
                FROM Part_time_emp
                WHERE eid = _eid;

                _monthly_salary := NULL;
                _amount := (_num_work_hours * _hourly_rate)::numeric;
                _amount := ROUND(_amount, 2);

            ELSE -- full-time employee
                _status := 'Full-time';

                -- compute number of days in a month
                SELECT (EXTRACT(DAYS FROM DATE_TRUNC('month', MAKE_DATE(_pay_year, _pay_month, 1))
                    + INTERVAL '1 month - 1 day'))::int
                INTO _num_of_days;

                -- compute number of work days
                SELECT join_date, depart_date
                INTO _join_date, _depart_date
                FROM Employees
                WHERE eid = _eid;

                IF _pay_month = (EXTRACT(MONTH FROM _join_date))::int
                    AND _pay_year = (EXTRACT(YEAR FROM _join_date))::int THEN
                    _first_work_day := (EXTRACT(DAY FROM _join_date))::int;
                ELSE
                    _first_work_day := 1;
                END IF;

                IF _pay_month = (EXTRACT(MONTH FROM _depart_date))::int
                    AND _pay_year = (EXTRACT(YEAR FROM _depart_date))::int THEN
                    _last_work_day := (EXTRACT(DAY FROM _depart_date))::int;
                ELSE
                    _last_work_day := _num_of_days;
                END IF;

                _num_work_days := _last_work_day - _first_work_day + 1;
                _num_work_hours := NULL;
                _hourly_rate := NULL;

                SELECT monthly_salary
                INTO _monthly_salary
                FROM Full_time_emp
                WHERE eid = _eid;

                _amount := (_num_work_days::numeric / _num_of_days * _monthly_salary)::numeric;
                _amount := ROUND(_amount, 2);

            END IF;

            -- add to output & table if
            IF (_amount <> 0) THEN
                RETURN NEXT;
                _pay_date := MAKE_DATE(_pay_year, _pay_month, _num_of_days);

                -- insert salary payment record
                INSERT INTO Pay_slips
                VALUES (_eid, _pay_date, _amount::numeric, _num_work_days, _num_work_hours);
            END IF;

        END IF;
    END LOOP;
    CLOSE curs;
END;
$$ LANGUAGE plpgsql;


-- ROUTINE 26
-- 1. Check for inactive customers
-- 2. For each inactive customer, find:
-- 	- Course area A, whereby at least one of the three most recent course offerings are in A
-- 	- If customer has not registered for any course offerings, every course area is of interest.
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
                fees         numeric
            )
AS
$$
WITH InActiveCust AS (SELECT cust_id, name
                      FROM combine_reg_redeems()
                               NATURAL JOIN Customers
                      GROUP BY cust_id, name
                      HAVING MAX(register_date) + INTERVAL '6 months' < CURRENT_DATE),
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
             FROM CustWithNoOfferings,
                  ValidOfferings

             UNION

             SELECT cust_id,
                    name,
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


-- ROUTINE 27
-- used to find the top N course packages for this year.
CREATE OR REPLACE FUNCTION top_packages(N int)
    RETURNS TABLE
            (
                package_id        int,
                num_free_sessions int,
                price             numeric,
                start_date        date,
                end_date          date,
                number_sold       bigint
            )
AS
$$
DECLARE
    curs         refcursor;
    r            record;
    prev_sold    int;
    current_year double precision;
BEGIN

    IF (N < 0) THEN
        RAISE EXCEPTION 'The given input N cannot be negative: %', N;
    END IF;

    -- get current year
    SELECT date_part
    INTO current_year
    FROM DATE_PART('year', CURRENT_DATE);

    CREATE TEMPORARY TABLE IF NOT EXISTS temp_table ON COMMIT DROP AS
    SELECT P.*, COALESCE(COUNT(buy_date), 0) AS number_sold
    FROM Course_packages P
             NATURAL LEFT JOIN Buys B
    WHERE DATE_PART('year', sale_start_date) = current_year
    GROUP BY P.package_id;

    OPEN curs FOR (
        SELECT *
        FROM temp_table
        ORDER BY number_sold DESC, price DESC
    );

    WHILE n >= 0
        LOOP
            FETCH curs INTO r;
            EXIT WHEN NOT found;

            EXIT WHEN n = 0 AND r.number_sold <> prev_sold;

            package_id := r.package_id;
            num_free_sessions := r.num_free_registrations;
            price := r.price;
            start_date := r.sale_start_date;
            end_date := r.sale_end_date;
            number_sold := r.number_sold;

            prev_sold := number_sold;
            IF (n > 0) THEN
                n := n - 1;
            END IF;
            RETURN NEXT;
        END LOOP;
END
$$ LANGUAGE plpgsql;


-- ROUTINE 28
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
     ValidOfferings AS (SELECT course_id, title, area_name, COALESCE(numReg, 0) AS numReg, start_date
                        FROM (Offerings NATURAL LEFT JOIN NumRegistered)
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


-- ROUTINE 29
-- Get summary report for the past N months
CREATE OR REPLACE FUNCTION view_summary_report(N int)
    RETURNS TABLE
            (
                _month                            text,
                _year                             int,
                _total_salary_paid                numeric,
                _total_sales_from_packages        numeric,
                _total_registration_fees          numeric,
                _total_refunded_registration_fees numeric,
                _total_redemption_count           int
            )
AS
$$
DECLARE
    _month_val int;
    _date_ptr  date;
BEGIN
    IF N < 0 THEN
        RAISE EXCEPTION 'Input to view summary report cannot be negative, provided value: %', N;
    END IF;

    _date_ptr := CURRENT_DATE;

    LOOP
        EXIT WHEN N = 0;

        _month_val := EXTRACT(MONTH FROM _date_ptr);
        _month := TO_CHAR(_date_ptr, 'Mon');
        _year := EXTRACT(YEAR FROM _date_ptr);

        -- Get total salary paid
        SELECT ROUND(COALESCE(SUM(amount), 0), 2)
        INTO _total_salary_paid
        FROM Pay_slips
        WHERE EXTRACT(MONTH FROM payment_date) = _month_val
          AND EXTRACT(YEAR FROM payment_date) = _year;

        -- Get total sales from course packages
        SELECT ROUND(COALESCE(SUM(price), 0), 2)
        INTO _total_sales_from_packages
        FROM Buys
                 NATURAL JOIN Course_packages
        WHERE EXTRACT(MONTH FROM buy_date) = _month_val
          AND EXTRACT(YEAR FROM buy_date) = _year;

        -- Get total registration fees paid using credit card
        SELECT ROUND(COALESCE(SUM(fees), 0), 2)
        INTO _total_registration_fees
        FROM Registers
                 NATURAL JOIN Offerings
        WHERE EXTRACT(MONTH FROM register_date) = _month_val
          AND EXTRACT(YEAR FROM register_date) = _year;

        -- Get total amount of registration_fees refunded
        SELECT ROUND(COALESCE(SUM(refund_amt), 0), 2)
        INTO _total_refunded_registration_fees
        FROM Cancels
        WHERE EXTRACT(MONTH FROM cancel_date) = _month_val
          AND EXTRACT(YEAR FROM cancel_date) = _year;

        -- Get total amount of redemptions
        SELECT COALESCE(COUNT(*), 0)
        INTO _total_redemption_count
        FROM Redeems
        WHERE EXTRACT(MONTH FROM redeem_date) = _month_val
          AND EXTRACT(YEAR FROM redeem_date) = _year;

        -- iterate to previous month
        _date_ptr := _date_ptr - INTERVAL '1 month';
        N := N - 1;

        RETURN NEXT;

    END LOOP;
END;
$$ LANGUAGE plpgsql;


-- ROUTINE 30
-- Get manager report for current year
CREATE OR REPLACE FUNCTION view_manager_report()
    RETURNS TABLE
            (
                _manager_name           text,
                _course_areas_total     int,
                _course_offerings_total int,
                _net_reg_fees_total     numeric,
                _top_course_title       text[]
            )
AS
$$
DECLARE
    curs CURSOR FOR (
        SELECT *
        FROM Employees
                 NATURAL JOIN Managers
        WHERE NOT is_departed(eid, DATE_TRUNC('year', CURRENT_DATE)::date)
        ORDER BY name);
    r record;
BEGIN
    OPEN curs;
    LOOP
        FETCH curs INTO r;
        EXIT WHEN NOT found;

        _manager_name := r.name;

        SELECT COUNT(area_name)
        INTO _course_areas_total
        FROM Course_areas
        WHERE eid = r.eid;

        -- Table to store all offerings managed by the manager that end this year
        CREATE TEMP TABLE Manager_offerings_this_year AS
        SELECT *
        FROM Offerings
        WHERE (SELECT EXTRACT(YEAR FROM end_date)) = (SELECT EXTRACT(YEAR FROM CURRENT_DATE))
          AND course_id IN (
            SELECT course_id
            FROM Courses
            WHERE area_name IN (
                SELECT area_name
                FROM Course_areas
                WHERE eid = r.eid));

        SELECT COUNT(launch_date)
        INTO _course_offerings_total
        FROM Manager_offerings_this_year;

        -- Table to store total registration fees for each offering
        -- managed by the manager and end this year
        CREATE TEMP TABLE Manager_offerings_registers AS
        SELECT launch_date, course_id, COALESCE(SUM(O.fees), 0) AS _offering_registration_fees
        FROM Manager_offerings_this_year O
                 NATURAL JOIN Registers R
        GROUP BY launch_date, course_id;

        -- Table to store total redemption fees for each offering
        -- managed by the manager and end this year
        CREATE TEMP TABLE Manager_offerings_packages AS
        WITH Manager_offerings_redeems AS (
            SELECT *
            FROM Manager_offerings_this_year
                     NATURAL JOIN Redeems)
        SELECT launch_date,
               course_id,
               COALESCE(SUM(P.price / P.num_free_registrations), 0) AS _offering_redemption_fees
        FROM Manager_offerings_redeems R
                 NATURAL JOIN Course_packages P
        GROUP BY launch_date, course_id;

        -- Table to store total net registration fees for each offering
        CREATE TEMP TABLE Manager_offerings_net_reg_fees AS
        SELECT launch_date,
               course_id,
               COALESCE(Reg._offering_registration_fees, 0) + COALESCE(P._offering_redemption_fees, 0) AS _net_reg_fees
        FROM Manager_offerings_registers Reg
                 NATURAL FULL JOIN Manager_offerings_packages P;


        SELECT ROUND(COALESCE(SUM(_net_reg_fees), 0), 2)
        INTO _net_reg_fees_total
        FROM Manager_offerings_net_reg_fees;

        _top_course_title := ARRAY(
                SELECT DISTINCT title
                FROM Courses
                WHERE course_id IN (
                    SELECT course_id
                    FROM Manager_offerings_net_reg_fees
                    WHERE _net_reg_fees IN (SELECT MAX(_net_reg_fees) FROM Manager_offerings_net_reg_fees)));

        RETURN NEXT;

        DROP TABLE Manager_offerings_net_reg_fees;
        DROP TABLE Manager_offerings_packages;
        DROP TABLE Manager_offerings_registers;
        DROP TABLE Manager_offerings_this_year;
    END LOOP;
    CLOSE curs;
END;
$$ LANGUAGE plpgsql;
