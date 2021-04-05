-- assume session_duration are in units of hour
CREATE OR REPLACE FUNCTION find_rooms(_session_date date, _session_start_hour time,
    _session_duration int)
RETURNS TABLE(_rid int) AS $$
DECLARE
    curs cursor for (select * from Rooms order by rid);
    r record;
    _session_start_time time;
    _session_end_time time;
BEGIN
    -- validate session_date
    if (select extract(isodow from _session_date) in (6, 7)) then
        raise exception 'Session date must be a weekday.';
    end if;

    -- validate session_start_time and session_end_time
    _session_start_time := _session_start_hour;
    _session_end_time := _session_start_hour + concat(_session_duration, ' hours')::interval;
    if (not (_session_start_time, _session_end_time) overlaps (time '09:00', time '18:00'))
        or (_session_start_time, _session_end_time) overlaps (time '12:00', time '14:00') then
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
            and session_date = _session_date
            and (start_time, end_time) overlaps (_session_start_time, _session_end_time)) then
            _rid := r.rid;
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
CREATE OR REPLACE FUNCTION get_available_rooms(_start_date date, _end_date date)
RETURNS TABLE(_rid int, _room_capacity int, _day date, _available_hours time[]) AS $$
DECLARE
    curs cursor for (select * from Rooms order by rid);
    r record;
    _hours_array int[];
    _hour int;
    _loop_date date;
    _temp_start_hour time;
    _temp_end_hour time;
BEGIN
    -- validate that _start_date is before _end_date
    if (_start_date > _end_date) then
        raise exception 'The start date cannot be after the end date.';
    end if;

    _hours_array := '{time 09:00, time 10:00, time 11:00, time 14:00, time 15:00, time 16:00, time 17:00}';

    open curs;
    -- loop each rid
    loop
        fetch curs into r;
        exit when not found;
        
        -- loop each day for the current rid
        _loop_date := _start_date;
        loop
            exit when _loop_date > _end_date;
            
            if (select extract(isodow from _loop_date) in (1, 2, 3, 4, 5)) then
                _rid = r.rid;
                _room_capacity := r.seating_capacity;
                _day := _loop_date;
                _available_hours := '{}';
                
                -- loop each hour for the current rid and day
                foreach _hour in array _hours_array
                loop
                    _temp_start_hour := _hour;
                    _temp_end_hour := _hour + interval '1 hour';

                    if not exists (
                        select 1
                        from Sessions
                        where rid = _rid
                        and session_date = _loop_date
                        and (start_time, end_time) overlaps (_temp_start_hour, _temp_end_hour)) then
                        _available_hours := array_append(_available_hours, _hour);
                    end if;
                end loop;

                return next;
            end if;

            _loop_date := _loop_date + 1;
        end loop;

    end loop;
    close curs;
END;
$$ LANGUAGE plpgsql;

-- launch_date is needed to differentiate between two sessions with the same
-- course id and same session number but offered at different times of the year
-- (i.e. different launch_date)
CREATE OR REPLACE PROCEDURE update_room(_cid int, _launch_date date, _session_num int, _new_rid int)
AS $$
DECLARE
    _session_date date;
    _session_time time;
    _new_room_capacity int;
    _num_of_redeem int;
    _num_of_register int;
    _num_of_cancel int;
BEGIN
    -- check if session exists
    if not exists (
        select 1
        from Sessions
        where course_id = _cid and launch_date = _launch_date and sid = _session_num) then
        raise exception 'Course session does not exist.';
    end if;

    -- check that session has not started yet
    select session_date, start_time into _session_date, _session_time
    from Sessions
    where course_id = _cid and launch_date = _launch_date and sid = _session_num;

    if _session_date < current_date
        or (_session_date = current_date and _session_time <= current_time) then
        raise exception 'Room is not updated as the session has already started.';
    end if;

    -- check if new_rid exists in Rooms
    if _new_rid not in (select rid from Rooms) then
        raise exception 'The new room does not exist in the Rooms table.';
    end if;

    -- check if number of registrations exceed seating capacity of new room
    select seating_capacity into _new_room_capacity
    from Rooms
    where rid = _new_rid;

    select count(cust_id) into _num_of_redeem
    from Redeems
    where course_id = _cid and launch_date = _launch_date and sid = _session_num;

    select count(cust_id) into _num_of_register
    from Registers
    where course_id = _cid and launch_date = _launch_date and sid = _session_num;

    select count(cust_id) into _num_of_cancel
    from Cancels
    where course_id = _cid and launch_date = _launch_date and sid = _session_num;

    if _new_room_capacity < (_num_of_redeem + _num_of_register - _num_of_cancel) then
        raise exception 'The number of registrations exceeds the seating capacity of the new room.';
    end if;

    -- update room for the session
    update Sessions
    set rid = _new_rid
    where course_id = _cid and launch_date = _launch_date and sid = _session_num;
END;
$$ LANGUAGE plpgsql;
