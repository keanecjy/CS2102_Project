/*
add_course:
add_course_offering:
get_available_course_offerings:
get_available_course_sessions:
update_course_session:
promote_courses:
popular_courses:
*/

-- Adds a course into the courses table
create or replace procedure add_course(course_title text, course_desc text, course_area text, duration integer)
AS
$$
insert into Courses
values (coalesce((select max(course_id) from Courses), 0) + 1, course_title, course_desc, course_area, duration);
$$ language sql;

-- /*
-- Check for
-- 1. Valid course offering
-- 2. Sufficient instructors to add all of sessions
-- - Use an array to keep track of all the new session_ids added. If one of the sessions fail to find an instructor,
-- we will rollback all the insertions into Sessions table.
-- 3. reg_deadline at least 10 days before start date
-- 4.
-- */

create or replace procedure add_course_offering(cid int, l_date date, fees float, reg_deadline date,
                                                admin_id int, sessions_arr text[][])
AS $$

DECLARE
    temp text[];
    course_area text;
    course_duration int;
    s_date date;
    s_time time;
    s_rid int;

    seat_capacity int;
    inst_eid int;
    next_sid int;
    earliest_start_date date;
    latest_end_date date;

BEGIN
    -- 	Checking validity of course offering information
    if (cid not in (select course_id from Courses)
        or fees < 0
        or (array_length(sessions_arr, 1) = 0)
        or (admin_id not in (select eid from Administrators))
        or (reg_deadline + 10 <= l_date)) then
        raise exception 'Course offering details are invalid';
    end if;

    select area_name, duration into course_area, course_duration from Courses  where course_id = cid;
    next_sid := 1;
    seat_capacity := 0;

    -- Temp insertion to allow adding of Sessions
    insert into Offerings
    values (l_date, cid, reg_deadline, null, null, admin_id, 0, 0, fees);

    -- Adding each session in
    foreach temp in array sessions_arr
        loop
            s_date := temp[1]::date;
            s_time := temp[2]::time;
            s_rid := temp[3];

            if (earliest_start_date is null or earliest_start_date > s_date) then
                earliest_start_date := s_date;
            end if;

            if (latest_end_date is null or latest_end_date < s_date) then
                latest_end_date := s_date;
            end if;

            -- Find an eid from the list of available instructors (do we need to find the most optimal?)
            select eid into inst_eid
            from find_instructors(cid, s_date, s_time)
            limit 1;

            if (inst_eid is null) then
                raise exception 'Not able to find instructor to allocate';
            end if;

            if (not exists(select 1 from Rooms where rid = s_rid)) then
                raise exception 'Room does not exist';
            end if;

            insert into Sessions
            values (next_sid, l_date, cid, s_date, s_time, s_time + course_duration, s_rid, inst_eid);

            seat_capacity := seat_capacity + (select seating_capacity from Rooms where rid = s_rid);
            inst_eid := null;
            next_sid := next_sid + 1;

        end loop;

    update Offerings
    set start_date = earliest_start_date,
        end_date = latest_end_date,
        target_number_registrations = seat_capacity,
        seating_capacity = seat_capacity
    where cid = course_id and launch_date = l_date;

END;

$$ language plpgsql;





