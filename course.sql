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

-- TODO: Add target num of registrations to params
create or replace procedure add_course_offering(cid int, l_date date, fees float, reg_deadline date,
                                                admin_id int, sessions_arr text[][])
AS
$$

DECLARE
    temp                text[];
    course_area         text;
    course_duration     int;
    s_date              date;
    s_time              time;
    s_rid               int;
    seat_capacity       int;
    inst_eid            int;
    next_sid            int;
    earliest_start_date date;
    latest_end_date     date;

BEGIN
    -- 	Checking validity of course offering information
    if (cid not in (select course_id from Courses)
        or fees < 0
        or (array_length(sessions_arr, 1) = 0)
        or (admin_id not in (select eid from Administrators))
        or (reg_deadline + 10 <= l_date)) then
        raise exception 'Course offering details are invalid';
    end if;

    select area_name, duration into course_area, course_duration from Courses where course_id = cid;
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
            select eid
            into inst_eid
            from find_instructors(cid, s_date, s_time)
            limit 1;

            if (inst_eid is null) then
                -- TODO: Cleanup by deleting previously added sessions?
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

    -- Update the course offerings record after all sessions are inserted
    update Offerings
    set start_date                  = earliest_start_date,
        end_date                    = latest_end_date,
        target_number_registrations = seat_capacity,
        seating_capacity            = seat_capacity
    where cid = course_id
      and launch_date = l_date;

END;

$$ language plpgsql;

-- Q15
-- Retrieves all course offerings that can be registered
-- Output is sorted in ascending order of registration deadline and course title.
-- Can be registered == seating_capacity - numRegistered > 0
create or replace function get_available_course_offerings()
    returns table
            (
                title                 text,
                area_name             text,
                start_date            date,
                end_date              date,
                registration_deadline date,
                fees                  float,
                remaining_seats       int
            )
AS
$$
with NumRegistered as (
    select course_id, launch_date, count(*) as numReg
    from ((select course_id, launch_date from Registers) union all (select course_id, launch_date from Redeems)) R
    group by course_id, launch_date
)

select title,
       area_name,
       start_date,
       end_date,
       registration_deadline,
       fees,
       seating_capacity - coalesce(numReg, 0)
from (Courses natural join Offerings)
         natural left join NumRegistered
where start_date >= current_date
  and seating_capacity - coalesce(numReg, 0) > 0;

$$ language sql;



-- Q16
-- Retrieve all the available sessions for a course offering that could be registered.
create or replace function get_available_course_sessions(cid int, date_of_launch date)
    returns table
            (
                session_date    date,
                start_time      time,
                inst_name       text,
                remaining_seats int
            )
AS
$$
select session_date, start_time, name, seating_capacity - get_num_registration_for_session(sid, date_of_launch, cid)
from (Sessions
    natural join Rooms)
         natural join Employees
where course_id = cid
  and launch_date = date_of_launch
  and session_date >= current_date
  and seating_capacity - get_num_registration_for_session(sid, date_of_launch, cid) > 0;

$$ language sql;



-- Helper function to query the num of registrations for the session
create or replace function get_num_registration_for_session(session_id int, date_launch date, cid int)
    returns int AS
$$
select count(*)
from ((select sid, launch_date, course_id from Redeems)
      union all
      (select sid, launch_date, course_id from Registers)) R
where sid = session_id
  and launch_date = date_launch
  and course_id = cid;
$$ language sql;


/*
Q19
1. Check for seat availability is done by trigger
2. Check if customers registered or redeemed for the session and update accordingly
3. Check for current_date before registration deadline

*/
create or replace procedure update_course_session(customer_id int, cid int, date_launch date, new_sid int)
AS
$$

BEGIN
    if (exists(select 1
               from Redeems
               where cust_id = customer_id
                 and course_id = cid
                 and launch_date = date_launch)) then

        update Redeems
        set sid         = new_sid,
            redeem_date = current_date
        where cust_id = customer_id
          and course_id = cid
          and launch_date = date_launch;
    else
        update Registers
        set sid         = new_sid,
            redeem_date = current_date
        where cust_id = customer_id
          and course_id = cid
          and launch_date = date_launch;
    end if;
END;
$$ language plpgsql;

