/**
 * Constraint trigger on Employees after insertion
 * -> to enforce covering and no overlap constraint:
 * an employee must be a part-time or full-time employee
 * -> to enforce that an employee is either an instructor, administrator or manager
 */
CREATE OR REPLACE FUNCTION insert_employee_cat_check()
RETURNS TRIGGER AS $$
DECLARE
    emp_count int; -- count occurrence of employee in Part_time_emp and Full_time_emp
    emp_type_count int; -- count occurrence of employee in Instructors, Administrators and Managers
BEGIN
    emp_count := 0;
    emp_type_count := 0;

    -- check emp_count
    if new.eid in (select eid from Part_time_emp) then
        emp_count := emp_count + 1;
    end if;

    if new.eid in (select eid from Full_time_emp) then
       emp_count := emp_count + 1;
    end if;

    if emp_count <> 1 then
        raise exception 'Employee % must be in either Part_time_emp or Full_time_emp table.', new.eid;
   end if;

    -- check emp_type_count
    if new.eid in (select eid from Instructors) then
        emp_type_count := emp_type_count + 1;
    end if;

    if new.eid in (select eid from Administrators) then
        emp_type_count := emp_type_count + 1;
    end if;

    if new.eid in (select eid from Managers) then
        emp_type_count := emp_type_count + 1;
    end if;

    if emp_type_count <> 1 then
        raise exception 'Employee % must be in either Instructors, Administrators or Managers table.', new.eid;
    end if;

    return new;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER insert_employee_cat_check
AFTER INSERT OR UPDATE ON Employees DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION insert_employee_cat_check();



/**
 * Constraint trigger on Part_time_instructors, Full_time_instructors,
 * Administrators and Managers after update or delete
 * -> to enforce that the old employee before update or delete is NOT in:
 *    1) Employees table AND
 *    2) either Part_time_emp or Full_time_emp table AND
 *    3) Instructors table if old employee is a part-time or full-time instructor
 *
 * NOTE: updating or deleting from Part_time_emp, Full_time_emp and Instructors
 * are not checked as:
 * 1) there will be a violation of foreign key constraint if there is a referenced tuple
 *    in either Part_time_instructors, Full_time_instructors, Administrators or Managers
 * 2) any update or delete from  Part_time_instructors, Full_time_instructors, Administrators
 *    or Managers must also be updated / deleted in its referencing tables
 */
CREATE OR REPLACE FUNCTION update_or_delete_employee_cat_check()
RETURNS TRIGGER AS $$
BEGIN
    -- If there is no change to eid, ignore the constraint check
    if (TG_OP = 'UPDATE' AND OLD.eid = NEW.eid) THEN
        return null;
    end if;

    if TG_TABLE_NAME = 'part_time_instructors' then
        if old.eid in (select eid from Instructors) or
            old.eid in (select eid from Part_time_emp) or
            old.eid in (select eid from Employees) then
            raise exception 'Part-time instructor % still exists in referenced tables.', old.eid;
        end if;
        return null;
    elsif TG_TABLE_NAME = 'full_time_instructors' then
        if old.eid in (select eid from Instructors) or
            old.eid in (select eid from Full_time_emp) or
            old.eid in (select eid from Employees) then
            raise exception 'Full-time instructor % still exists in referenced tables.', old.eid;
        end if;
        return null;
    elsif TG_TABLE_NAME = 'administrators' then
        if old.eid in (select eid from Full_time_emp) or
            old.eid in (select eid from Employees) then
            raise exception 'Administrator % still exists in referenced tables.', old.eid;
        end if; 
        
        return null;
    elsif TG_TABLE_NAME = 'managers' then
        if old.eid in (select eid from Full_time_emp) or
            old.eid in (select eid from Employees) then
            raise exception 'Manager % still exists in referenced tables.', old.eid;
        end if;
        
        return null;
    else
        raise exception 'Internal error in update_or_delete_employee_cat_check';
    end if;

END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER update_or_delete_employee_cat_check
AFTER UPDATE OR DELETE ON Part_time_instructors DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION update_or_delete_employee_cat_check();

CREATE CONSTRAINT TRIGGER update_or_delete_employee_cat_check
AFTER UPDATE OR DELETE ON Full_time_instructors DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION update_or_delete_employee_cat_check();

CREATE CONSTRAINT TRIGGER update_or_delete_employee_cat_check
AFTER UPDATE OR DELETE ON Administrators DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION update_or_delete_employee_cat_check();

CREATE CONSTRAINT TRIGGER update_or_delete_employee_cat_check
AFTER UPDATE OR DELETE ON Managers DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION update_or_delete_employee_cat_check();



/**
 * Constraint trigger on Part_time_emp
 * -> to enforce covering and no overlap constraint:
 * a part-time employee is a part-time instructor
 */
CREATE OR REPLACE FUNCTION part_time_emp_check()
RETURNS TRIGGER AS $$
BEGIN
    if new.eid not in (select eid from Part_time_instructors) then
        raise exception 'Part-time employee % must be in Part_time_instructors table.', new.eid;
    end if;

    return new;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER part_time_emp_check
AFTER INSERT OR UPDATE ON Part_time_emp DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION part_time_emp_check();



/**
 * Constraint trigger on Full_time_emp
 * -> to enforce covering and no overlap constraint:
 * a full-time employee is either a full-time instructor, administrator or manager
 */
CREATE OR REPLACE FUNCTION full_time_emp_check()
RETURNS TRIGGER AS $$
DECLARE
    full_time_count int; -- count occurrence of full-time employee in Full_time_instructors, Administrators and Managers
BEGIN
    full_time_count := 0;

    if new.eid in (select eid from Full_time_instructors) then
        full_time_count := full_time_count + 1;
    end if;

    if new.eid in (select eid from Administrators) then
        full_time_count := full_time_count + 1;
    end if;

    if new.eid in (select eid from Managers) then
        full_time_count := full_time_count + 1;
    end if;

    if full_time_count <> 1 then
        raise exception 'Full-time employee % must be in either Full_time_instructors, Administrators or Managers table.', new.eid;
    end if;

    return new;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER full_time_emp_check
AFTER INSERT OR UPDATE ON Full_time_emp DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION full_time_emp_check();



/**
 * Constraint trigger on Instructors
 * -> to enforce covering and no overlap constraint:
 * an instructor is either a part-time or full-time instructor
 */
CREATE OR REPLACE FUNCTION instructor_check()
RETURNS TRIGGER AS $$
DECLARE
    inst_count int;
BEGIN
    inst_count := 0;

    if new.eid in (select eid from Part_time_instructors) then
        inst_count := inst_count + 1;
    end if;

    if new.eid in (select eid from Full_time_instructors) then
        inst_count := inst_count + 1;
    end if;

    if inst_count <> 1 then
        raise exception 'Instructor % must be in either Part_time_instructors or Full_time_instructors table.', new.eid;
    end if;

    return new;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER instructor_check
AFTER INSERT OR UPDATE ON Instructors DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION instructor_check();



/**
 * Constraint trigger on Employees
 * -> to enforce valid update of an employee's departure date
 * condition for validity is from function 2 (remove_employee)
 */
CREATE OR REPLACE FUNCTION update_employee_departure()
RETURNS TRIGGER AS $$
BEGIN
    -- If departure date is already null, ignore the constraint check
    if (TG_OP = 'UPDATE' AND OLD.depart_date is not null) THEN
        return new;
    end if;

    -- condition 1
    if new.eid in (select eid from Administrators)
        and new.depart_date < any (
            select registration_deadline
            from Offerings
            where eid = new.eid) then
        raise notice 'Departure date for employee id % is not updated as the administrator is handling some course offering where its registration deadline is after the departure date.', new.eid;
        return null;
    -- condition 2
    elsif new.eid in (select eid from Instructors)
        and new.depart_date < any (
            select session_date
            from Sessions
            where eid = new.eid) then
       raise notice 'Departure date for employee id % is not updated as the instructor is teaching some course session that starts after the departure date.', new.eid;
       return null;
    -- condition 3
    elsif new.eid in (select eid from Managers)
        and new.eid in (select eid from Course_areas) then
        raise notice 'Departure date for employee id % is not updated as the manager is still managing some course area.', new.eid;
        return null;
    else
        return new;
    end if;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_employee_departure
BEFORE INSERT OR UPDATE ON Employees
FOR EACH ROW WHEN (new.depart_date is not null)
EXECUTE FUNCTION update_employee_departure();



/**
 * Constraint trigger on Instructors
 * -> to enforce total participation:
 * every instructor has >= 1 specialization
 */
CREATE OR REPLACE FUNCTION at_least_one_specialization()
RETURNS TRIGGER AS $$
BEGIN
    if TG_TABLE_NAME = 'instructors' then
        IF (new.eid not in (select eid from Specializes)) then
            raise exception 'Instructor % must specialise in at least one course area.', new.eid;
        END IF;
    else
        if old.eid in (select eid from Instructors) and
            old.eid not in (select eid from Specializes) then
            raise exception 'Instructor % must specialise in at least one course area.', old.eid;
        end if;
    end if;

    return null;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER at_least_one_specialization
AFTER INSERT OR UPDATE ON Instructors DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION at_least_one_specialization();

CREATE CONSTRAINT TRIGGER at_least_one_specialization
AFTER UPDATE OR DELETE ON Specializes DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION at_least_one_specialization();



/**
 * Constraint trigger on Credit_cards
 *  -> to enforce total participation, every customer have at least one card
 */
CREATE OR REPLACE FUNCTION at_least_one_card()
RETURNS TRIGGER AS $$
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
$$ language plpgsql;

CREATE CONSTRAINT TRIGGER at_least_one_card
AFTER INSERT OR UPDATE ON Customers DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION at_least_one_card();

CREATE CONSTRAINT TRIGGER at_least_one_card
AFTER DELETE OR UPDATE ON Credit_cards DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION at_least_one_card();



/**
 * Enforce that each customer can have at most one active or partially active package
 */
CREATE OR REPLACE FUNCTION at_most_one_package()
RETURNS TRIGGER AS $$
DECLARE
    num_packages int;
BEGIN

    SELECT COUNT(*) INTO num_packages
    FROM Buys B
    WHERE cust_id = NEW.cust_id AND
        (num_remaining_redemptions > 0 OR
            EXISTS(SELECT 1
                FROM Redeems R NATURAL JOIN Sessions S
                WHERE R.buy_date = B.buy_date AND
                    R.cust_id = B.cust_id AND
                    R.package_id = B.package_id AND
                    current_date + 7 <= S.session_date));

    IF (num_packages > 1) THEN
        RAISE EXCEPTION 'Customer % can only have at most one active or partially active package', NEW.cust_id;
    END IF;

    RETURN NEW;
END;
$$ language plpgsql;

CREATE CONSTRAINT TRIGGER at_most_one_package
AFTER INSERT OR UPDATE ON Buys DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION at_most_one_package();



/*
Trigger to check for inserting/updating a registration/redemption of session.
1) Check if current_date have already past the session_date itself
2) Check if current_date have already past the registration_deadline
3) Check if number of registration + redeems <= seating_capacity
4) Check if customer register for more than 1 session in this course offering.
*/
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

    -- Check if current_date have already past the session_date or registration deadline
    IF (CURRENT_DATE > s_date OR CURRENT_DATE > deadline) THEN
        RAISE EXCEPTION 'It is too late to register for this session!';
    END IF;
    
    -- Check if there is enough slots in the session
    IF (get_num_registration_for_session(new.sid, new.launch_date, new.course_id) > seat_cap) THEN
        RAISE EXCEPTION 'Session % with Course id: % and launch date: % is already full', new.sid, new.course_id, new.launch_date;
    END IF;

    -- Checks if customer has already registered for the session
    IF (num_registered >= 2) THEN
        raise EXCEPTION 'Customer has already registered for a session in this course offering!';
    END IF;
    RETURN new;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER valid_session
    AFTER INSERT OR UPDATE
    ON Redeems
    FOR EACH ROW
EXECUTE FUNCTION reg_redeem_check();

CREATE TRIGGER valid_session
    AFTER INSERT OR UPDATE
    ON Registers
    FOR EACH ROW
EXECUTE FUNCTION reg_redeem_check();



-- to ensure that course offerings will have >= 1
CREATE OR REPLACE FUNCTION after_insert_into_offerings()
    RETURNS TRIGGER AS
$$
BEGIN
    IF (NOT EXISTS (SELECT 1 FROM Sessions S WHERE S.launch_date = NEW.launch_date AND S.course_id = NEW.course_id)) THEN
        RAISE EXCEPTION 'There isnt any session in this course offerings: %', NEW.course_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER after_insert_into_offerings
AFTER INSERT OR UPDATE ON Offerings DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION after_insert_into_offerings();



-- Handles refund of registrations if it is eligible for refund
CREATE OR REPLACE FUNCTION after_delete_of_registers()
    RETURNS TRIGGER AS
$$
DECLARE
    date_of_session DATE;
    cost float;
BEGIN
    SELECT S.session_date INTO date_of_session
    FROM Sessions S
    WHERE S.sid = OLD.sid
      AND S.course_id = OLD.course_id
      AND S.launch_date = OLD.launch_date;

    IF (current_date + 7 <= date_of_session) THEN
        select fees into cost FROM Offerings WHERE course_id = OLD.course_id AND launch_date = OLD.launch_date;
        INSERT INTO Cancels VALUES (now(), 0.9 * cost, null, OLD.cust_id, OLD.sid, OLD.launch_date, OLD.course_id);
    ELSE
        INSERT INTO Cancels VALUES (now(), 0, null, OLD.cust_id, OLD.sid, OLD.launch_date, OLD.course_id);
    end if;
    RETURN NULL;
END;    
$$ LANGUAGE plpgsql;

CREATE TRIGGER after_delete_of_registers
AFTER DELETE ON Registers
FOR EACH ROW EXECUTE FUNCTION after_delete_of_registers();


/**
 * - Maintain the redemption count of customer's active/partially active package.
 * - Enforce that each customer can have at most one active or partially active package
 */
CREATE OR REPLACE FUNCTION modify_redeem_check()
    RETURNS TRIGGER AS $$
DECLARE
    date_of_session DATE;
    num_packages int;
BEGIN
    IF TG_OP = 'INSERT' THEN
        -- udpate redemption count
        UPDATE Buys B
        SET num_remaining_redemptions = num_remaining_redemptions - 1
        WHERE (B.buy_date, B.cust_id, B.package_id) = (NEW.buy_date, NEW.cust_id, NEW.package_id);

    ELSIF TG_OP = 'UPDATE' THEN

        IF ((NEW.buy_date, NEW.cust_id, NEW.package_id) <> (OLD.buy_date, OLD.cust_id, OLD.package_id)) THEN
            RAISE EXCEPTION 'Cannot directly modify package type for redeems table';
        END IF;

        -- Enforce that update maintains the at most one active/partially active constraint
        SELECT COUNT(*) INTO num_packages
        FROM Buys B
        WHERE cust_id = NEW.cust_id AND
            (num_remaining_redemptions > 0 OR
             EXISTS(SELECT 1
                    FROM Redeems R NATURAL JOIN Sessions S
                    WHERE R.buy_date = B.buy_date AND
                            R.cust_id = B.cust_id AND
                            R.package_id = B.package_id AND
                            current_date + 7 <= S.session_date));

        IF (num_packages > 1) THEN
            RAISE EXCEPTION 'Updating the course session will result in multiple active/partially active package for Customer %', NEW.cust_id
                USING HINT = 'Use register_session and cancel_session to add and remove redeemed sessions';
        END IF;

    ELSE
        -- DELETE

        SELECT session_date into date_of_session
        FROM Sessions
        WHERE (sid, course_id, launch_date) = (OLD.sid, OLD.course_id, OLD.launch_date);

        -- handle the cancellation of session
        IF (current_date + 7 <= date_of_session) THEN
            UPDATE Buys B
            SET num_remaining_redemptions = num_remaining_redemptions + 1
            WHERE (B.buy_date, B.cust_id, B.package_id) = (NEW.buy_date, NEW.cust_id, NEW.package_id);

            INSERT INTO Cancels VALUES (now(), null, 1, OLD.cust_id, OLD.sid, OLD.launch_date, OLD.course_id);
        ELSE
            INSERT INTO Cancels VALUES (now(), null, 0, OLD.cust_id, OLD.sid, OLD.launch_date, OLD.course_id);
        END IF;

    END IF;

END;
$$ language plpgsql;

CREATE CONSTRAINT TRIGGER modify_redeem_check
AFTER INSERT OR UPDATE OR DELETE ON Redeems DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION modify_redeem_check();
