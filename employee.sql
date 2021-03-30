DROP TRIGGER IF EXISTS employee_trigger ON Employees CASCADE; 

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
CREATE OR REPLACE PROCEDURE add_employee(name text, phone int, email text, address text,
    join_date date, salary_info float, employee_cat text,
    variadic course_areas text[] default null)
AS $$
DECLARE
    eid int;
    area_name text;
BEGIN
    -- validate employee_cat
    if employee_cat not in ('Manager', 'Administrator', 'Part-time instructor',
        'Full-time instructor') then
        raise exception 'Employee category must be from the following set: {Manager, Administrator, Part-time instructor, Full-time instructor}.';
    end if;

    -- validate course_areas
    if employee_cat in ('Administrator') then
        if course_areas is not null then
            raise exception 'The set of course areas must be empty for an administrator.';
        end if;
    else -- manager / instructor
        if course_areas is null then
            raise exception 'The set of course areas cannot be empty for a manager or instructor.';
        end if;
    end if;

    -- generate id
    select coalesce(max(eid), 0) + 1 into eid
    from Employees;

    -- insert into relevant tables
    insert into Employees
    values (eid, name, phone, email, address, join_date, null);

    if employee_cat = 'Manager' then
        insert into Full_time_emp
        values (eid, salary_info); -- assumed to be monthly salary

        insert into Managers
        values (eid);

        foreach area_name in array course_areas
        loop
            insert into Course_areas
            values (area_name, eid);
        end loop;
    elseif employee_cat = 'Administrator' then
        insert into Full_time_emp
        values (eid, salary_info); -- assumed to be monthly salary

        insert into Administrators
        values (eid);
    elseif employee_cat = 'Part-time instructor' then
        insert into Part_time_emp
        values (eid, salary_info); -- assumed to be hourly rate

        insert into Instructors
        values (eid);

        insert into Part_time_instructors
        values (eid);

        foreach area_name in array course_areas
        loop
            insert into Specializes
            values (eid, area_name);
        end loop;
    else -- full-time instructor
        insert into Full_time_emp
        values (eid, salary_info); -- assumed to be monthly salary

        insert into Instructors
        values (eid);

        insert into Full_time_instructors
        values (eid);

        foreach area_name in array course_areas
        loop
            insert into Specializes
            values (eid, area_name);
        end loop;
    end if;
END;
$$ LANGUAGE plpgsql;

-- Checking if update operation on Employees is valid is done by employee_trigger.
CREATE OR REPLACE PROCEDURE remove_employee(eid int, depart_date date)
AS $$
BEGIN
    update Employees
    set depart_date = depart_date
    where eid = eid;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION employee_trigger_func()
RETURNS TRIGGER AS $$
BEGIN
    -- condition 1
    if new.eid in (select eid from Administrators)
        and new.depart_date < any (
            select registration_deadline
            from Offerings
            where eid = new.eid) then
        raise notice 'Departure date for employee id % is not updated.', eid;
        return null;
    -- condition 2
    elseif new.eid in (select eid from Instructors)
        and new.depart_date < any (
            select session_date
            from Sessions
            where eid = new.eid) then
       raise notice 'Departure date for employee id % is not updated.', eid;
       return null;
    -- condition 3
    elseif new.eid in (select eid from Managers)
        and new.eid in (select eid from Course_areas) then
        raise notice 'Departure date for employee id % is not updated.', eid;
        return null;
    else
        return new;
    end if;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER employee_trigger
BEFORE UPDATE ON Employees
FOR EACH ROW
WHEN (new.depart_date is not null)
EXECUTE FUNCTION employee_trigger_func();

-- Number of work hours for a part-time instructor is computed based on the number of hours
-- the part-time instructor taught at all sessions for that particular month and year.
CREATE OR REPLACE FUNCTION pay_salary(pay_month int, pay_year int)
RETURNS TABLE(eid int, name text, status text, num_work_days int, num_work_hours int,
    hourly_rate float, monthly_salary float, amount float) AS $$
DECLARE
    curs cursor for (select * from employees order by eid);
    r record;
    num_of_days int;
    join_date date;
    depart_date date;
    first_work_day int;
    last_work_day int;
    pay_date date;
BEGIN
    open curs;
    loop
        fetch curs into r;
        exit when not found;
        
        eid := r.eid;
        name := r.name;

        if eid in (select eid from Part_time_emp) then
            status := 'Part-time';
            num_work_days := null;
            
            -- compute number of hours worked by the part-time instructor
            -- assume start_time and end_time are in units of hour
            select sum(extract(hour from end_time) - extract(hour from start_time))::int
                into num_work_hours
            from Sessions
            where eid = eid
            and pay_month = (extract(month from session_date))::int
            and pay_year = (extract(year from session_date))::int;

            select hourly_rate into hourly_rate
            from Part_time_emp
            where eid = eid;

            monthly_salary := null;
            amount := num_work_hours * hourly_rate;

            return next;
        else -- full-time employee
            status := 'Full-time';

            -- compute number of days in a month
            select (extract(days from date_trunc('month', make_date(pay_year, pay_month, 1))
                    + interval '1 month - 1 day'))::int into num_of_days;

            -- compute number of work days
            select join_date, depart_date into join_date, depart_date
            from Employees
            where eid = eid;

            if pay_month = (extract(month from join_date))::int
                and pay_year = (extract(year from join_date))::int then
                first_work_day := (extract(day from join_date))::int;
            else
                first_work_day := 1;
            end if;

            if pay_month = (extract(month from depart_date))::int
                and pay_year = (extract(year from depart_date))::int then
                last_work_day := (extract(day from depart_date))::int;
            else
                last_work_day := num_of_days;
            end if;

            num_work_days := last_work_day - first_work_day + 1;
            num_work_hours := null;
            hourly_rate := null;

            select monthly_salary into monthly_salary
            from Full_time_emp
            where eid = eid;

            amount := num_work_days / num_of_days * monthly_salary;
            
            return next;
        end if;

        -- insert salary payment record
        pay_date := make_date(pay_year, pay_month, num_of_days);
        insert into Pay_slips
        values (eid, pay_date, amount, num_work_days, num_work_hours);

    end loop;
    close curs;
END;
$$ LANGUAGE plpgsql;
