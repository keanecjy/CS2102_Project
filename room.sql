-- assume session_start_hour and session_duration are in units of hour
CREATE OR REPLACE FUNCTION find_rooms(session_date date, session_start_hour int,
    session_duration int)
RETURNS TABLE(rid int) AS $$
DECLARE
    curs cursor for (select * from Rooms order by rid);
    r record;
    session_start_time time;
    session_end_time time;
BEGIN
    -- validate session_date
    if (select extract(isodow from session_date) in (6, 7)) then
        raise exception 'Session date must be a weekday.';
    end if;

    -- validate session_start_time and session_end_time
    session_start_time := make_time(session_start_hour, 0, 0);
    session_end_time := make_time(session_start_hour + session_duration, 0, 0);
    if not (session_start_time, session_end_time) overlaps (time '09:00', time '18:00')
        or (session_start_time, session_end_time) overlaps (time '12:00', time '14:00') then
        raise exception 'Session start time and/or duration is/are invalid.';
    end if;

    open curs;
    loop
        fetch curs into r;
        exit when not found;

        -- assume start_time and end_time are in units of hour
        if not exists (
            select 1
            from Sessions
            where rid = r.rid
            and session_date = session_date
            and (r.start_time, r.end_time) overlaps (session_start_time, session_end_time)) then
            rid := r.rid;
            return next;
        end if;
    end loop;
    close curs;
END;
$$ LANGUAGE plpgsql;

-- assume a room is only available during the weekday from 9am to 6pm (except 12pm to 2pm)
--
-- day record in output table is of date type as the start_date and end_date may span more
-- than a month
--
-- each entry in the available_hours array is an integer denoting 1 hour from the entry's
-- hour value (e.g. 10 means 10:00 to 11:00)
--
-- assume available_hours are in units of hours
CREATE OR REPLACE FUNCTION get_available_rooms(start_date date, end_date date)
RETURNS TABLE(rid int, room_capacity int, day date, available_hours int[]) AS $$
DECLARE
    curs cursor for (select * from Rooms order by rid);
    r record;
    hours_array int[];
    hour int;
    loop_date date;
    temp_start_hour time;
    temp_end_hour time;
BEGIN
    hours_array := '{9, 10, 11, 14, 15, 16, 17}';

    open curs;
    -- loop each rid
    loop
        fetch curs into r;
        exit when not found;
        
        -- loop each day for the current rid
        loop_date := start_date;
        loop
            exit when loop_date > end_date;
            
            if (select extract(isodow from loop_date) in (1, 2, 3, 4, 5)) then
                rid = r.rid;
                room_capacity := r.seating_capacity;
                day := loop_date;
                available_hours := '{}';
                
                -- loop each hour for the current rid and day
                foreach hour in array hours_array
                loop
                    temp_start_hour := make_time(hour, 0, 0);
                    temp_end_hour := make_time(hour + 1, 0, 0);

                    if not exists (
                        select 1
                        from Sessions
                        where rid = rid
                        and (temp_start_hour, temp_end_hour) overlaps (start_time, end_time)) then
                        select array_append(available_hours, hour);
                    end if;
                end loop;

                return next;
            end if;

            loop_date := loop_date + 1;
        end loop;

    end loop;
END;
$$ LANGUAGE plpgsql;

-- launch_date is needed to differentiate between two sessions with the same
-- course id and same session number but offered at different times of the year
-- (i.e. different launch_date)
CREATE OR REPLACE PROCEDURE update_room(cid int, launch_date date, session_num int, new_rid int)
AS $$
DECLARE
    session_date date;
    session_time time;
    new_room_capacity int;
    num_of_redeem int;
    num_of_register int;
    num_of_cancel int;
BEGIN
    -- check that session has not started yet
    select session_date, start_time into session_date, session_time
    from Sessions
    where course_id = cid and launch_date = launch_date and sid = session_num;

    if session_date < current_date
        or (session_date = current_date and session_time <= current_time) then
        raise exception 'Room is not updated as the session has already started.';
    end if;

    -- check if new_rid exists in Rooms
    if new_rid not in (select rid from Rooms) then
        raise exception 'The new room does not exist in the Rooms table.';
    end if;

    -- check if number of registrations exceed seating capacity of new room
    select seating_capacity into new_room_capacity
    from Rooms
    where rid = new_rid;

    select count(cust_id) into num_of_redeem
    from Redeems
    where course_id = cid and launch_date = launch_date and sid = session_num;

    select count(cust_id) into num_of_register
    from Registers
    where course_id = cid and launch_date = launch_date and sid = session_num;

    select count(cust_id) into num_of_cancel
    from Cancels
    where course_id = cid and launch_date = launch_date and sid = session_num;

    if new_room_capacity < (num_of_redeem + num_of_register - num_of_cancel) then
        raise exception 'The number of registrations exceeds the seating capacity of the new room.';
    end if;

    -- update room for the session
    update Sessions
    set rid = new_rid
    where course_id = cid and launch_date = launch_date and sid = session_num;
END;
$$ LANGUAGE plpgsql;
