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
    _salary_info float, _join_date date, _employee_cat text,
    variadic _course_areas text[] default null)
AS $$
DECLARE
    _eid int;
    _area_name text;
BEGIN
    -- validate _employee_cat
    if _employee_cat not in ('Manager', 'Administrator', 'Part-time instructor',
        'Full-time instructor') then
        raise exception 'Employee category must be from the following set: {Manager, Administrator, Part-time instructor, Full-time instructor}.';
    end if;

    -- validate _course_areas
    if _employee_cat in ('Administrator') then
        if _course_areas is not null then
            raise exception 'The set of course areas must be empty for an administrator.';
        end if;
    elseif _employee_cat in ('Manager') then
        -- the set of course area can be empty as a manager can manage zero course area
        foreach _area_name in array _course_areas
        loop
            -- the course area cannot be managed by another manager
            if _area_name in (select area_name from Course_areas) then
                raise exception '% is managed by another manager.', _area_name;
            end if;
        end loop;
   else -- instructor
        if _course_areas is null then
            raise exception 'The set of course areas cannot be empty for an instructor.';
        end if;
    end if;

    -- generate id
    select coalesce(max(eid), 0) + 1 into _eid
    from Employees;

    -- insert into relevant tables
    insert into Employees
    values (_eid, _name, _phone, _email, _address, _join_date, null);

    if _employee_cat = 'Manager' then
        insert into Full_time_emp
        values (_eid, _salary_info); -- assumed to be monthly salary

        insert into Managers
        values (_eid);

        foreach _area_name in array _course_areas
        loop
            insert into Course_areas
            values (_area_name, _eid);
        end loop;
    elseif _employee_cat = 'Administrator' then
        insert into Full_time_emp
        values (_eid, _salary_info); -- assumed to be monthly salary

        insert into Administrators
        values (_eid);
    elseif _employee_cat = 'Part-time instructor' then
        insert into Part_time_emp
        values (_eid, _salary_info); -- assumed to be hourly rate

        insert into Instructors
        values (_eid);

        insert into Part_time_instructors
        values (_eid);

        foreach _area_name in array _course_areas
        loop
            insert into Specializes
            values (_eid, _area_name);
        end loop;
    else -- full-time instructor
        insert into Full_time_emp
        values (_eid, _salary_info); -- assumed to be monthly salary

        insert into Instructors
        values (_eid);

        insert into Full_time_instructors
        values (_eid);

        foreach _area_name in array _course_areas
        loop
            insert into Specializes
            values (_eid, _area_name);
        end loop;
    end if;
END;
$$ LANGUAGE plpgsql;

-- Checking if update operation on Employees is valid is done by employee_trigger.
CREATE OR REPLACE PROCEDURE remove_employee(_eid int, _depart_date date)
AS $$
BEGIN
    update Employees
    set depart_date = _depart_date
    where eid = _eid;
END;
$$ LANGUAGE plpgsql;

-- Number of work hours for a part-time instructor is computed based on the number of hours
-- the part-time instructor taught at all sessions for that particular month and year.
CREATE OR REPLACE FUNCTION pay_salary()
RETURNS TABLE(_eid int, _name text, _status text, _num_work_days int, _num_work_hours int,
    _hourly_rate float, _monthly_salary float, _amount float) AS $$
DECLARE
    curs cursor for (select * from employees order by eid);
    r record;
    _pay_month int;
    _pay_year int;
    _num_of_days int;
    _join_date date;
    _depart_date date;
    _first_work_day int;
    _last_work_day int;
    _pay_date date;
BEGIN
    _pay_month := extract(month from current_date)::int;
    _pay_year := extract(year from current_date)::int;

    open curs;
    loop
        fetch curs into r;
        exit when not found;
        
        _eid := r.eid;
        _name := r.name;

        if _eid in (select eid from Part_time_emp) then
            _status := 'Part-time';
            _num_work_days := null;
            
            -- compute number of hours worked by the part-time instructor
            -- assume start_time and end_time are in units of hour
            select sum(extract(hour from end_time) - extract(hour from start_time))::int
                into _num_work_hours
            from Sessions
            where eid = _eid
            and _pay_month = (extract(month from session_date))::int
            and _pay_year = (extract(year from session_date))::int;

            select hourly_rate into _hourly_rate
            from Part_time_emp
            where eid = _eid;

            _monthly_salary := null;
            _amount := _num_work_hours * _hourly_rate;

            return next;
        else -- full-time employee
            _status := 'Full-time';

            -- compute number of days in a month
            select (extract(days from date_trunc('month', make_date(_pay_year, _pay_month, 1))
                    + interval '1 month - 1 day'))::int into _num_of_days;

            -- compute number of work days
            select join_date, depart_date into _join_date, _depart_date
            from Employees
            where eid = _eid;

            if _pay_month = (extract(month from _join_date))::int
                and _pay_year = (extract(year from _join_date))::int then
                _first_work_day := (extract(day from _join_date))::int;
            else
                _first_work_day := 1;
            end if;

            if _pay_month = (extract(month from _depart_date))::int
                and _pay_year = (extract(year from _depart_date))::int then
                _last_work_day := (extract(day from _depart_date))::int;
            else
                _last_work_day := _num_of_days;
            end if;

            _num_work_days := _last_work_day - _first_work_day + 1;
            _num_work_hours := null;
            _hourly_rate := null;

            select monthly_salary into _monthly_salary
            from Full_time_emp
            where eid = _eid;

            _amount := _num_work_days / _num_of_days * _monthly_salary;
            
            return next;
        end if;

        -- insert salary payment record
        _pay_date := make_date(_pay_year, _pay_month, _num_of_days);
        insert into Pay_slips
        values (_eid, _pay_date, _amount, _num_work_days, _num_work_hours);

    end loop;
    close curs;
END;
$$ LANGUAGE plpgsql;
