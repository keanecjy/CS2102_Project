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

create or replace procedure print_array(sessions_arr text[][])
AS
$$

DECLARE
    temp   text[];
    s_date date;
    s_time time;
    num    int;
-- yyyy-mm-dd
BEGIN

    foreach temp slice 1 in array sessions_arr
        loop
            s_date := temp[1]::date;
            s_time := temp[2]::time;
            num := temp[3];
            raise notice 'Date: %, Time: %, rid: %', s_date, s_time, num;
            raise notice 'Array is %', temp;
        end loop;

END;

$$ language plpgsql;

call print_array('{{20201211, 18:00, 1}, {2021-01-11, 15:00, 2}}');



