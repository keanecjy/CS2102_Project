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

DROP TRIGGER IF EXISTS insert_employee_cat_check on Employees;

CREATE CONSTRAINT TRIGGER insert_employee_cat_check
AFTER INSERT ON Employees DEFERRABLE INITIALLY DEFERRED
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
    if TG_TABLE_NAME = 'Part_time_instructors' then
        if old.eid in (select eid from Instructors) or
            old.eid in (select eid from Part_time_emp) or
            old.eid in (select eid from Employees) then
            raise exception 'Part-time instructor % still exists in referenced tables.', old.eid;
        end if;
    elseif TG_TABLE_NAME = 'Full_time_instructors' then
         if old.eid in (select eid from Instructors) or
            old.eid in (select eid from Full_time_emp) or
            old.eid in (select eid from Employees) then
            raise exception 'Full-time instructor % still exists in referenced tables.', old.eid;
        end if;
    elseif TG_TABLE_NAME = 'Administrators' then
         if old.eid in (select eid from Full_time_emp) or
            old.eid in (select eid from Employees) then
            raise exception 'Administrator % still exists in referenced tables.', old.eid;
        end if; 
    else -- Managers
         if old.eid in (select eid from Full_time_emp) or
            old.eid in (select eid from Employees) then
            raise exception 'Manager % still exists in referenced tables.', old.eid;
        end if;
    end if;

    return null;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_or_delete_employee_cat_check on Part_time_instructors;
DROP TRIGGER IF EXISTS update_or_delete_employee_cat_check on Full_time_instructors;
DROP TRIGGER IF EXISTS update_or_delete_employee_cat_check on Administrators;
DROP TRIGGER IF EXISTS update_or_delete_employee_cat_check on Managers;

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

DROP TRIGGER IF EXISTS part_time_emp_check on Part_time_emp;

CREATE CONSTRAINT TRIGGER part_time_emp_check
AFTER INSERT ON Part_time_emp DEFERRABLE INITIALLY DEFERRED
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

DROP TRIGGER IF EXISTS full_time_emp_check on Full_time_emp;

CREATE CONSTRAINT TRIGGER full_time_emp_check
AFTER INSERT ON Full_time_emp DEFERRABLE INITIALLY DEFERRED
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

DROP TRIGGER IF EXISTS instructor_check on Instructors;

CREATE CONSTRAINT TRIGGER instructor_check
AFTER INSERT ON Instructors DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION instructor_check();



/**
 * Constraint trigger on Employees
 * -> to enforce valid update of an employee's departure date
 * condition for validity is from function 2 (remove_employee)
 */
CREATE OR REPLACE FUNCTION update_employee_departure()
RETURNS TRIGGER AS $$
BEGIN
    -- condition 1
    if new.eid in (select eid from Administrators)
        and new.depart_date < any (
            select registration_deadline
            from Offerings
            where eid = new.eid) then
        raise notice 'Departure date for employee id % is not updated as the administrator is handling some course offering where its registration deadline is after the departure date.', new.eid;
        return null;
    -- condition 2
    elseif new.eid in (select eid from Instructors)
        and new.depart_date < any (
            select session_date
            from Sessions
            where eid = new.eid) then
       raise notice 'Departure date for employee id % is not updated as the instructor is teaching some course session that starts after the departure date.', new.eid;
       return null;
    -- condition 3
    elseif new.eid in (select eid from Managers)
        and new.eid in (select eid from Course_areas) then
        raise notice 'Departure date for employee id % is not updated as the manager is still managing some course area.', new.eid;
        return null;
    else
        return new;
    end if;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_employee_departure ON Employees;

CREATE TRIGGER update_employee_departure
BEFORE UPDATE ON Employees
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
    if TG_OP = 'INSERT' and TG_TABLE_NAME = 'Instructors' THEN
        if new.eid not in (select eid from Specializes) then
            raise exception 'Instructor % must specialise in at least one course area.', new.eid;
        end if;
    end if;

    if (TG_OP = 'UPDATE' or TG_OP 'DELETE') and TG_TABLE_NAME = 'Specializes' then
        if old.eid in (select eid from Instructors) and
            old.eid not in (select eid from Specializes) then
            raise exception 'Instructor % must specialise in at least one course area.', old.eid;
        end if;
    end if;

    return null;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS at_least_one_specialization on Instructors;
DROP TRIGGER IF EXISTS at_least_one_specialization on Specializes;

CREATE TRIGGER at_least_one_specialization
AFTER INSERT ON Instructors
FOR EACH ROW EXECUTE FUNCTION at_least_one_specialization();

CREATE TRIGGER at_least_one_specialization
AFTER UPDATE OR DELETE ON Specializes
FOR EACH ROW EXECUTE FUNCTION at_least_one_specialization();



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
END;
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
END;
$$ language plpgsql;


DROP TRIGGER IF EXISTS at_most_one_package on Buys;

CREATE CONSTRAINT TRIGGER at_most_one_package AFTER INSERT OR UPDATE ON Buys
FOR EACH ROW
EXECUTE FUNCTION at_most_one_package();



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


DROP TRIGGER IF EXISTS valid_session ON Redeems;
DROP TRIGGER IF EXISTS valid_session ON Registers;

CREATE CONSTRAINT TRIGGER valid_session
    AFTER INSERT OR UPDATE
    ON Redeems
    FOR EACH ROW
EXECUTE FUNCTION reg_redeem_check();

CREATE CONSTRAINT TRIGGER valid_session
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
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER after_insert_into_offerings
AFTER INSERT OR UPDATE ON Offerings DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION after_insert_into_offerings();
