CREATE OR REPLACE FUNCTION view_summary_report(N int)
RETURNS TABLE (_month text, _year int, _total_salary_paid float,
    _total_sales_from_packages float, _total_registration_fees float,
    _total_refunded_registration_fees float, _total_redemption_count int) AS $$
DECLARE
    _month_val int;
    _date_ptr date;
BEGIN
    if N < 0 then
        raise exception 'Input to view summary report cannot be negative, provided value: %', N;
    end if;

    _date_ptr := current_date;

    loop
        exit when N = 0;

        _month_val := extract (month from _date_ptr);
        _month := to_char (_date_ptr, 'Mon');
        _year := extract (year from _date_ptr);

        -- Get total salary paid
        select coalesce(sum(amount), 0) into _total_salary_paid
        from Pay_slips
        where extract (month from payment_date) = _month_val and
            extract (year from payment_date) = _year;

        -- Get total sales from course packages
        select coalesce(sum(price), 0) into _total_sales_from_packages
        from Buys natural join Course_packages 
        where extract (month from buy_date) = _month_val and
            extract (year from buy_date) = _year;

        -- Get total registration fees paid using credit card
        select coalesce(sum(fees), 0) into _total_registration_fees
        from Registers natural join Offerings
        where extract (month from register_date) = _month_val and
            extract (year from register_date) = _year;

        -- Get total amount of registration_fees refunded
        select coalesce(sum(refund_amt), 0) into _total_refunded_registration_fees
        from Cancels
        where extract (month from cancel_date) = _month_val and
            extract (year from cancel_date) = _year;

        -- Get total amount of redemptions
        select coalesce(count(*), 0) into _total_redemption_count
        from Redeems
        where extract (month from redeem_date) = _month_val and
            extract (year from redeem_date) = _year;

        -- iterate to previous month
        _date_ptr := _date_ptr - interval '1 month';
        N := N - 1;
       _total_registration_fees := _total_registration_fees + _total_refunded_registration_fees;

        return next;

    end loop;
END;
$$ LANGUAGE plpgsql;




CREATE OR REPLACE FUNCTION view_manager_report()
RETURNS TABLE (_manager_name text, _course_areas_total int, _course_offerings_total int,
    _net_reg_fees_total float, _top_course_title text[]) AS $$
DECLARE
    curs cursor for (
        select *
        from Employees
        where eid in (select eid from Managers)
        order by name);
    r record;
    _registration_fees float;
    _refunded_fees float;
    _redemption_fees float;
BEGIN
    open curs;
    loop
        fetch curs into r;
        exit when not found;
        
        _manager_name := r.name;

        select count(area_name) into _course_areas_total
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

        select count(launch_date) into _course_offerings_total
        from Manager_offerings_this_year;

        -- Table to store total registration fees for each offering
        -- managed by the manager and end this year
        create temp table Manager_offerings_registers as
            select launch_date, course_id, coalesce(sum(O.fees), 0) as _offering_registration_fees
            from Manager_offerings_this_year O natural join Registers R
            group by launch_date, course_id;

        -- Table to store total redemption fees for each offering
        -- managed by the manager and end this year
        create temp table Manager_offerings_packages as
            with Manager_offerings_redeems as (
                select *
                from Manager_offerings_this_year natural join Redeems)
           select launch_date, course_id,
                coalesce(sum(P.price / P.num_free_registrations), 0) as _offering_redemption_fees
            from Manager_offerings_redeems R natural join Course_packages P
            group by launch_date, course_id;

        -- Table to store total net registration fees for each offering
        create temp table Manager_offerings_net_reg_fees as
            select launch_date, course_id,
                coalesce(Reg._offering_registration_fees, 0) + coalesce(P._offering_redemption_fees, 0) as _net_reg_fees
            from Manager_offerings_registers Reg natural full join Manager_offerings_packages P;


        select coalesce(sum(_net_reg_fees), 0) into _net_reg_fees_total
        from Manager_offerings_net_reg_fees;

        _top_course_title := ARRAY(
            select distinct title
            from Courses
            where course_id in (
                select course_id
                from Manager_offerings_net_reg_fees
                where _net_reg_fees in (select max(_net_reg_fees) from Manager_offerings_net_reg_fees)));

        return next;

        drop table Manager_offerings_net_reg_fees;
        drop table Manager_offerings_packages;
        drop table Manager_offerings_registers;
        drop table Manager_offerings_this_year;
    end loop;
    close curs;
END;
$$ LANGUAGE plpgsql;
