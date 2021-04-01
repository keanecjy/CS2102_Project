CREATE OR REPLACE FUNCTION view_manager_report()
RETURNS TABLE(manager_name text, course_areas_total int, course_offerings_total int,
    net_reg_fees_total float, top_course_title text[]) AS $$
DECLARE
    curs cursor for (
        select *
        from Employees
        where eid in (select eid from Managers)
        order by name);
    r record;
    registration_fees float;
    refunded_fees float;
    redemption_fees float;
BEGIN
    open curs;
    loop
        fetch curs into r;
        exit when not found;
        
        manager_name := r.name;

        select count(area_name) into course_areas_total
        from Course_areas
        where eid = r.eid;

        -- Table to store all offerings managed by the manager that end this year
        create temp table Manager_offerings_this_year as
            select *
            from Offerings
            where (select extract(year from end_date)) = (select extract(year from current_date))
            and course_id in (
                select course_id
                from Courses
                where area_name in (
                    select area_name
                    from Course_areas
                    where eid = r.eid));

        select count(launch_date) into course_areas_total
        from Manager_offerings_this_year;

        -- Table to store total registration fees for each offering
        -- managed by the manager and end this year
        create temp table Manager_offerings_registers as
            select launch_date, course_id, sum(O.fees) as offering_registration_fees
            from Manager_offerings_this_year O natural join Registers R
            group by launch_date, course_id;

        -- Table to store total redemption fees for each offering
        -- managed by the manager and end this year
        create temp table Manager_offerings_packages as
            with Manager_offerings_redeems as (
                select *
                from Manager_offerings_this_year natural join Redeems)
           select launch_date, course_id,
                sum(P.price / P.num_free_registrations) as offering_redemption_fees
            from Manager_offerings_redeems R natural join Course_packages P
            group by launch_date, course_id;

        -- Table to store total net registration fees for each offering
        create temp table Manager_offerings_net_reg_fees as
            select launch_date, course_id,
                R.offering_registration_fees + P.offering_redemption_fees as net_reg_fees
            from Manager_offerings_registers R natural join Manager_offerings_packages P;

        select sum(net_reg_fees) into net_reg_fees_total
        from Manager_offerings_net_reg_fees;

        top_course_title := ARRAY(
            select distinct title
            from Courses
            where course_id in (
                select course_id
                from Manager_offerings_net_reg_fees));

        return next;

        drop table Manager_offerings_net_reg_fees;
        drop table Manager_offerings_packages;
        drop table Manager_offerings_registers;
        drop table Manager_offerings_this_year;
    end loop;
    close curs;
END;
$$ LANGUAGE plpgsql;
